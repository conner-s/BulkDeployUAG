<#
.SYNOPSIS
Script to bulk deploy Unified Access Gateway appliances.
Requires
	*uagdeploy.ps1 and uagdeploy.psm1 scripts provided with the VMware UAG download in the same directory as this script.
	*ovftool installed
	*UAG ini files
	*settings.ini file

.USAGE
     .\BulkDeployUAG.ps1 [vCenterUser] [vCenterPassword]
     
     WHERE
         vCenterUser      = Username for vCenter Server.
         vCenterPassword  = Password for vCenter Server user.

.EXAMPLES
     .\BulkDeployUAG.ps1
     .\BulkDeployUAG.ps1 administrator@vsphere.local Password

 .NOTES
    Version:        2.2
    Author:         Graeme Gordon - ggordon@vmware.com
    Creation Date:  2023/08/30
    Purpose/Change: Bulk deploy or update Unified Access Gateway Appliances
  
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
    VMWARE,INC. BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 #>

#Requires -Version 3.0


param([string] $vCenterUser, [SecureString] $vCenterPassword )

#region variables
################################################################################
# Define default values for variables                                          #
################################################################################
$SettingsFile 				= "settings.ini"
$global:ovaimage			= ""
#endregion variables

function ImportIni
{
################################################################################
# Function to parse token values from a .ini configuration file                #
################################################################################
	param ($file)

	$ini = @{}
	switch -regex -file $file
	{
            "^\s*#" {
                continue
            }
    		"^\[(.+)\]$" {
        		$section = $matches[1]
        		$ini[$section] = @{}
    		}
    		"([A-Za-z0-9#_]+)=(.+)" {
        		$name,$value = $matches[1..2]
        		$ini[$section][$name] = $value.Trim()
    		}
	}
	$ini
}

function Get_Folder ($InitialDir)
{
################################################################################
# Function to use FolderBrowserDialog to get directory where INI files are     #
################################################################################
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null
	$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
	$dialog.SelectedPath = $InitialDir
	$dialog.ShowNewFolderButton = $False
	if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK)
	{
		$directoryName = $dialog.SelectedPath
		Write-Host ("Directory Selected        : " + $directoryName) -ForegroundColor Green
		return $directoryName
	}
	else { return $InitialDir }
}

function Get_File ($InitialDir)
{
################################################################################
# Function to use OpenFileDialog to get a file                                 #
################################################################################
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null
	$dialog = New-Object System.Windows.Forms.OpenFileDialog
	$dialog.initialDirectory = $InitialDir
	$dialog.ShowDialog() | Out-Null
    return $dialog.FileName
}

Function GenerateUAGList ($inifolder)
{
################################################################################
# Function Generate list of UAGs from the INI files in the chosen folder       #
################################################################################
	$global:uaglist = Get-ChildItem -Path $inifolder -Filter *.ini -Name
}

function Define_GUI
{
################################################################################
#              Function Define_GUI                                             #
################################################################################
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $global:form                     = New-Object System.Windows.Forms.Form
    $form.Text                       = 'Bulk Deploy Unified Access Gateway Appliances'
    $form.Size                       = New-Object System.Drawing.Size(500,400)
    #$form.Autosize                   = $true
    $form.StartPosition              = 'CenterScreen'
    $form.Topmost                    = $true

    #OK button
    $OKButton                        = New-Object System.Windows.Forms.Button
    $OKButton.Location               = New-Object System.Drawing.Point(300,320)
    $OKButton.Size                   = New-Object System.Drawing.Size(75,23)
    $OKButton.Text                   = 'OK'
    $OKButton.DialogResult           = [System.Windows.Forms.DialogResult]::OK
    $form.AcceptButton               = $OKButton
    $form.Controls.Add($OKButton)

    #Cancel button
    $CancelButton                    = New-Object System.Windows.Forms.Button
    $CancelButton.Location           = New-Object System.Drawing.Point(400,320)
    $CancelButton.Size               = New-Object System.Drawing.Size(75,23)
    $CancelButton.Text               = 'Cancel'
    $CancelButton.DialogResult       = [System.Windows.Forms.DialogResult]::Cancel
    $form.CancelButton = $CancelButton
    $form.Controls.Add($CancelButton)
	
    #Browse for INI Folder button
    $IniFolderButton                 = New-Object System.Windows.Forms.Button
    $IniFolderButton.Location        = New-Object System.Drawing.Point(300,40)
    $IniFolderButton.Size            = New-Object System.Drawing.Size(150,23)
    $IniFolderButton.Text             = 'Select INI Directory'
    $IniFolderButton.Add_Click({ 
		$global:inifolder = Get_Folder $global:inifolder
		GenerateUAGList ($global:inifolder)
		$listbox.Items.Clear()
		ForEach ($uag in $uaglist)
		{
			[void] $listBox.Items.Add($uag)
		}
		$form.Controls.Add($listBox)
	})
    $form.Controls.Add($IniFolderButton)
	
    #Browse for OVA Image button
    $OVAButton                       = New-Object System.Windows.Forms.Button
    $OVAButton.Location              = New-Object System.Drawing.Point(300,80)
    $OVAButton.Size                	 = New-Object System.Drawing.Size(150,23)
    $OVAButton.Text              	 = 'Select OVA Image'
	$OVAButton.Add_Click({
		$global:ovaimage = Get_File $global:ovafolder
		Write-Host ("OVA Image                 : " + $ovaimage) -ForegroundColor Green
	})
    $form.Controls.Add($OVAButton)

    #Checkbox on whether to update the target string
    $global:TargetSelect               = New-Object System.Windows.Forms.CheckBox
    $TargetSelect.Location             = New-Object System.Drawing.Point(300,200)
    $TargetSelect.Size                 = New-Object System.Drawing.Size(200,23)
    $TargetSelect.Text                 = 'Update Target Credentials'
	$TargetSelect.Checked              = $global:updatetarget
    $TargetSelect.Add_CheckStateChanged({ $global:updatetarget = $TargetSelect.Checked })
    $form.Controls.Add($TargetSelect) 

    #Checkbox on whether to demo actions
    $global:DemoSelect               = New-Object System.Windows.Forms.CheckBox
    $DemoSelect.Location             = New-Object System.Drawing.Point(300,240)
    $DemoSelect.Size                 = New-Object System.Drawing.Size(200,23)
    $DemoSelect.Text                 = 'Demo'
	$DemoSelect.Checked              = $global:demo
    $DemoSelect.Add_CheckStateChanged({ $global:demo = $DemoSelect.Checked })
    $form.Controls.Add($DemoSelect) 

    #Text above list box of VMs
    $label                           = New-Object System.Windows.Forms.Label
    $label.Location                  = New-Object System.Drawing.Point(10,20)
    $label.Size                      = New-Object System.Drawing.Size(280,20)
    $label.Text                      = 'Select UAGs from the list below:'
    $form.Controls.Add($label)

    #List box for selection of VMs
    $global:listBox                  = New-Object System.Windows.Forms.Listbox
    $listBox.Location                = New-Object System.Drawing.Point(10,40)
    $listBox.Size                    = New-Object System.Drawing.Size(260,250)
    $listBox.SelectionMode           = 'MultiExtended'
    ForEach ($uag in $uaglist)
    {
        [void] $listBox.Items.Add($uag)
    }
    $listBox.Height = 250
    $form.Controls.Add($listBox)  
}

function UpdateINI ($uag)
{
################################################################################
# Update the settings INI file for this UAG                                    #
################################################################################
	$UAGFileName = $inifolder + "\" + $uag
	Write-Host ("Input UAG File Name       : " + $UAGFileName) -ForegroundColor Yellow
	$uagini = ImportIni $UAGFileName #Read INI file for the UAG

	#Replace variables with specific info for this UAG
	$uagini.General.source = $ovaimage
	
	if ($updatetarget) #Create custom target string
	{
		$vCenterPassword
		$oldtarget = $uagini.General.target
		#Write-Host ("Old Target : " + $oldtarget) -ForegroundColor Green
		$atposition = $oldtarget.LastIndexOf('@')
		$targetpath = $oldtarget.Substring($atposition,$oldtarget.Length-$atposition)
		#Write-Host ("Target Path : " + $targetpath) -ForegroundColor Green
		If (!$vCenterUser) { $vCenterUser = $settings.vCenter.DefaultUser }
		If (!$vCenterPassword) { $vCenterPassword = $settings.vCenter.DefaultPassword }
		$uagini.General.target = "vi://" + $vCenterUser + [char]58 + $vCenterPassword  + $targetpath
	}
	
	#Create a runtime version of the INI file
	$RuntimeUAGFileName = $runtimefolder + "\" + $uag
	Write-Host ("Creating runtime INI file : " + $RuntimeUAGFileName) -ForegroundColor Yellow
	Set-Content -path $RuntimeUAGFileName -value ""
	
	#Write the sections and the settings to the file
	Foreach ($section in $uagini.Keys)
	{
		Add-Content -path $RuntimeUAGFileName -value ("[" + $section + "]")
		Foreach ($item in $uagini.$section.Keys)
		{
			Add-Content -path $RuntimeUAGFileName -value ($item + "=" + $uagini.$section.$item)
		}
		Add-Content -path $RuntimeUAGFileName -value ""
	}
	return $RuntimeUAGFileName
}


#region main
################################################################################
# Main Region                                                                  #
################################################################################
Clear-Host

#Check the settings file exists
if (!(Test-path $SettingsFile)) {
	Write-Error "Error: Configuration file ($iniFile) not found."
	Exit
}
#Import settings and apply to the variables
$settings				= ImportIni $SettingsFile
$global:inifolder		= $settings.Files.inifolder
if (!(Test-path $inifolder)) {
	$global:inifolder		= ""
}
$global:runtimefolder	= $settings.Files.runtimefolder
if (!(Test-path $runtimefolder)) {
	Write-Host ("Create runtime INI folder : " + $runtimefolder) -ForegroundColor Green
	New-Item -Path $runtimefolder -Type Directory
}
$global:ovafolder		= $settings.Files.ovafolder
$global:uagdeployscript	= $settings.Files.uagdeployscript
if (!(Test-path $uagdeployscript)) {
	Write-Error "Error: UAG Deploy ps1 script ($uagdeployscript) not found."
	Exit
}
If ($settings.Controls.updatetarget -eq "Yes") { $global:updatetarget = $True } else { $global:updatetarget = $False }
If ($settings.Controls.demo -eq "Yes") { $global:demo = $True } else { $global:demo = $False }

#Generate the list of UAGs from the INI files in the inifolder
GenerateUAGList $inifolder

#Define the UI and show it
Define_GUI
$result = $form.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK)
{
    If ($ovaimage)
	{ 
		$selection = $listBox.SelectedItems   
		If ($selection)
		{
			Write-Host ("Selected UAGs             : " + $selection) -ForegroundColor Yellow
			Write-Host ("Update Target Credentials : " + $updatetarget) -ForegroundColor Green
			Write-Host ("Demo                      : " + $demo) -ForegroundColor Green

			Add-Type -AssemblyName 'PresentationFramework'
            #Create an arraylist to hold the jobs
            $jobarray = New-Object System.Collections.ArrayList
            $jobCount = 0 #Create a counter for the jobs
			#Remove all jobs created if any lingered.
			Get-Job | Remove-Job
			$MaxThreads = 4
 			ForEach ($uag in $uaglist)
			{
 				If ($selection.Contains($uag))
 				{
 					Write-Host ("Deploying                 : " + $uag) -ForegroundColor Yellow
					$RuntimeUAGFileName = UpdateINI $uag
					If (!$demo) 
					{
						#Keep starting jobs until we reach the maximum number of threads.
						if ($(Get-Job -state running).count -lt $MaxThreads)
						{

                            $scriptParameters = @{
                                iniFile = $RuntimeUAGFileName
                                rootPwd = $settings.Deployment.rootPwd
                                adminPwd = $settings.Deployment.adminPwd
                                DisableVerification = $settings.Deployment.disableVerification
                                NoSSLVerify = $settings.Deployment.noSSLVerify
                                CeipEnabled = $settings.Deployment.ceipEnabled
                                AwAPIServerPwd = $settings.Deployment.awAPIServerPwd
                                AwTunnelGatewayAPIServerPwd = $settings.Deployment.awTunnelGatewayAPIServerPwd
                                AwTunnelProxyAPIServerPwd = $settings.Deployment.awTunnelProxyAPIServerPwd
                                AwCGAPIServerPwd = $settings.Deployment.awCGAPIServerPwd
                                AwSEGAPIServerPwd = $settings.Deployment.awSEGAPIServerPwd
                                NewAdminUserPwd = $settings.Deployment.newAdminUserPwd
                            }
                            #Needs absolute path to script, as opposed to relative path
                            [string]$path = Get-Location
                            $path += "\uagdeploy.ps1"
							$job = Start-Job -ScriptBlock ([scriptblock]::create("&'$path'  $(&{$args}@scriptParameters)"))
                            $jobarray.Add($job)
                            $jobarray
                            $jobCount++
						} else {
							Wait-Job
						}
					}
				}
			}
            #TODO load a new form with tabs for each thread and receive job on them to show progress and pump out the output with Receive-Job on a timer until each job completes.
			
		} else { Write-Host ("No UAGs Selected") -ForegroundColor Yellow }
	} else { Write-Host ("No OVA Image Selected") -ForegroundColor Yellow }
} else { Write-Host ("Cancel Button Pressed") -ForegroundColor Red }
#endregion main