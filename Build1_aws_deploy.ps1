#Import AWS powershell module
import-module awspowershell

#Enforce working in our current Jenkins workspace.
cd $env:WORKSPACE

#
#ENV:AWS_Profile is from the build parameters earlier it provides the AWS profile credentials
#

$aws_profile = $ENV:AWS_Profile
Set-AWSCredentials -ProfileName $aws_profile



#Load all the other environment variables AWS needs to to create an instance

$region = $ENV:Region
$instance_name = $ENV:Instance_Name
$builder = $ENV:BUILD_USER
$buildtag = $ENV:BUILD_TAG
$image_type = $ENV:image_type
$Instance_Type = $ENV:Instance_Type
$domain = $ENV:Domain
$Key_pair = $ENV:Key_Pair
$SecurityGroup = $ENV:Security_Group

#Search for the Security group Name tag Value. More on this in the next post.

try {
$SecurityGroup_Id = Get-EC2SecurityGroup -Region "$region" | where { $_.Groupname -eq "$SecurityGroup" } | select -expandproperty GroupId
echo "Security group Identification response:"
$SecurityGroup_Id

} catch {
$_
exit 1
}

#Make sure that the Instance name is not blank.

if($instance_name.length -le 1) {
echo "ERROR: Instance must be named and the length must be greater than 1."
echo "ERROR: Instance name: $instance_name"
echo "ERROR: Instance name length" $instance_name.length
exit 1
}

#Select AWS AMI. This is limited to the ones owned by Amazon. And gets the most up to date image.

try {
$image_id = Get-EC2Image -Owner amazon, self -Region $region | where { $_.Description -eq $image_type } | select -first 1 -expandproperty ImageId
echo "EC2 Image ID Response:"
$image_id
} catch {
$_
exit 1
}

#Generate the instance, with all environmental variables provided from Jenkins build.

try {
$instance_info = New-EC2Instance -ImageId $image_id -MinCount 1 -MaxCount 1 -KeyName $Key_pair -SecurityGroupId $SecurityGroup_Id -InstanceType $instance_type -Region $region
echo "Image generation response"
$instance_info
} catch {
$_
exit 1
}

#Let the user know things are working as intended and to please wait while we wait for the instance to reach the running state.

echo "Please wait for image to fully generate"
while($(Get-Ec2instance -instanceid $instance_info.instances.instanceid -region $region).Instances.State.Name.value -ne "running") {
sleep 1
}

#Once EC2 instance is created tags are added that are visible in the AWS console

echo "Naming Instance"
$tag = New-Object Amazon.EC2.Model.Tag
$tag.Key = "Name"
$tag.Value = "$instance_name"

New-EC2Tag -Resource $instance_info.instances.instanceid -Tag $tag -Region $region
echo "Tagging build information"
$tag.Key = "BuiltBy"
$tag.Value = "$builder"
New-EC2Tag -Resource $instance_info.instances.instanceid -Tag $tag -Region $region

$tag.Key = "BuildTag"
$tag.Value = "$BUILDTAG"

New-EC2Tag -Resource $instance_info.instances.instanceid -Tag $tag -Region $region

#Attach an elastic IP to the instance

try {
$ellastic_ip_allocation = New-EC2Address -Region $region
echo "Elastip IP registered:"
$ellastic_ip_allocation
} catch {
echo "ERROR: Registering Ec2Address"
$_
exit 1
#return $false
}

#Assign the elastic IP to the instance

try {
$response = Register-Ec2Address -instanceid $instance_info.instances.instanceid -AllocationID $ellastic_ip_allocation.allocationid -Region $region
echo "Register EC2Address Response:"
$response
} catch {
echo "ERROR: Associating EC2Address:"
$_
exit 1
}

#Send the elastic IP value to the EnvInj plugin:

$PublicIP = $ellastic_ip_allocation | select -expandproperty PublicIP
echo "Passing Env variable $PublicIP"
"ElasticIP = $PublicIP" | Out-file build.prop -Encoding ASCII -force

exit 0