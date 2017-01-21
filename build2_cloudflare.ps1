$email = "<Provided by CloudFlare Account>"
$api_key = "<Provided by CloudFlare Account>"

#Configure work environment and populate environment variables:
cd $env:WORKSPACE
$EIP = $env:ElasticIP
$domain_partial = $ENV:Domain
$domain_Instance_Name = $ENV:Instance_Name
$domain_FQDN = $domain_Instance_Name + "." + $domain_partial


$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Content-Type", "application/json")
$headers.Add("X-Auth-Key", "$api_key")
$headers.Add("X-Auth-Email", "$email")


function get-cfzoneid() {
Param(
	[string] $DNSname
)

	if($result = invoke-restmethod -Uri "https://api.cloudflare.com/client/v4/zones/" -Method GET  -headers $headers | select result) {
		if($DNSname.count -ge 1) {
			$dns_tmp = $DNSname.split(".")
			$zone = $dns_Tmp[$dns_tmp.count-2] + "." + $dns_Tmp[$dns_tmp.count-1]
		}
		
		if ($id = $result.result | where { $_.name -match $zone} | select -expandproperty id) {
			return $id
		} else {
			return $false
		}
	}
}

function create-CFdns() {
Param(
  [Parameter(Mandatory=$true)]
  [string] $DNSname,
  [Parameter(Mandatory=$true)]
  [string] $type,
  [Parameter(Mandatory=$true)]
  [string] $ip_update,
  [string] $id="NS"
  )
$uri_base = "https://api.cloudflare.com/client/v4/zones/" + $id

	if(-not($result = invoke-restmethod -Uri "$uri_base/dns_records" -Method GET  -headers $headers)) {
		return $false
	}

	if(-not ($result.result | where { $_.name -eq "$DNSname"})) {
		try {
			$json = "{""type"":""" + $type +""",
					 ""name"":""" + $dnsname + """,
					 ""content"":""" + $ip_update + """ }"
			$result = invoke-restmethod -Uri "https://api.cloudflare.com/client/v4/zones/$id/dns_records/" -Method POST -Body $json -headers $headers
			return $result.result
		} catch {
			return $false
		}
	} else {
		return $false
	}
}

function update-CFdns() {
Param(
  [Parameter(Mandatory=$true)]
  [string] $DNSname,
  [Parameter(Mandatory=$true)]
  [string] $ip_update,
  [string] $id="NS"
  )

$uri_base = "https://api.cloudflare.com/client/v4/zones/" + $id

	if($id -eq "NS") {
	$id = get-cfzoneid $DNSname
	}

	if(-not ($result = invoke-restmethod -Uri "$uri_base/dns_records" -Method GET  -headers $headers)) {
	return $false
	}

	if($data = $result.result | where { $_.name -eq "$DNSname"}) {
		try {
			$data | add-member "content" "$ip_update" -force
			$json = $data | ConvertTo-Json
			$query_url = $uri_base + "/dns_records/" + $data.id
			$result = invoke-restmethod -Uri $query_url -Method PUT -Body $json -headers $headers
			return $result.result
		} catch {
			return $_
		}
	} else {
		return $false
	}
}

try {
$id = get-cfzoneid $domain_FQDN
if(-not(update-CFdns $domain_FQDN $EIP $id)){
create-CFdns $domain_FQDN A $EIP $id
}
echo "Assigned $EIP to $domain_FQDN"
} catch {
echo "ERROR Assigning $EIP to $domain_FQDN"
$_
exit 1
}