# ====================== CONFIGURATION ======================
$PASSWORD_FOR_USERS = "Password1"
$USER_FIRST_LAST_LIST = Get-Content .\names.txt -ErrorAction Stop

$BaseOUName = "_USERS"

# Departments with Job Titles
$Departments = @{
    "Marketing" = @{
        Description = "Marketing Department"
        Titles = @("Marketing Manager", "Digital Marketing Specialist", "Content Writer", "SEO Specialist", 
                   "Brand Strategist", "Social Media Coordinator", "Marketing Analyst")
    }
    "Finance" = @{
        Description = "Finance Department"
        Titles = @("Finance Manager", "Accountant", "Financial Analyst", "Accounts Payable Specialist", 
                   "Auditor", "Payroll Specialist", "Budget Analyst")
    }
    "IT" = @{
        Description = "Information Technology"
        Titles = @("IT Manager", "System Administrator", "Network Engineer", "Help Desk Technician", 
                   "Cybersecurity Analyst", "Software Developer", "Database Administrator")
    }
    "HR" = @{
        Description = "Human Resources"
        Titles = @("HR Manager", "Talent Acquisition Specialist", "HR Generalist", "Payroll Coordinator", 
                   "Employee Relations Specialist", "Training Coordinator")
    }
    "Maintenance" = @{
        Description = "Maintenance Department"
        Titles = @("Maintenance Supervisor", "Facilities Technician", "Electrician", "HVAC Technician", 
                   "Janitorial Supervisor", "Maintenance Planner")
    }
    "Operations" = @{
        Description = "Operations Department"
        Titles = @("Operations Manager", "Logistics Coordinator", "Supply Chain Analyst", "Project Coordinator")
    }
    "Sales" = @{
        Description = "Sales Department"
        Titles = @("Sales Manager", "Account Executive", "Sales Representative", "Business Development Manager")
    }
}

# ------------------------------------------------------
Import-Module ActiveDirectory -ErrorAction Stop

$password = ConvertTo-SecureString $PASSWORD_FOR_USERS -AsPlainText -Force
$DomainDN = ([ADSI]"").distinguishedName

# Create Base OU
if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$BaseOUName'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $BaseOUName -Path $DomainDN -ProtectedFromAccidentalDeletion $false
    Write-Host "Created base OU: $BaseOUName" -ForegroundColor Green
}

# Create Department OUs and Groups
foreach ($deptName in $Departments.Keys) {
    $dept = $Departments[$deptName]
    $OUPath = "OU=$deptName,OU=$BaseOUName,$DomainDN"

    try { New-ADOrganizationalUnit -Name $deptName -Path "OU=$BaseOUName,$DomainDN" -ProtectedFromAccidentalDeletion $false -ErrorAction Stop } 
    catch { if ($_.Exception.Message -notlike "*already exists*") { Write-Warning $_.Exception.Message } }

    try { New-ADGroup -Name $deptName -GroupScope Global -GroupCategory Security -Path $OUPath -ErrorAction Stop } 
    catch { if ($_.Exception.Message -notlike "*already exists*") { Write-Warning $_.Exception.Message } }
}

# ====================== USER CREATION ======================
$usersCreated = @()   # Store user objects for manager assignment later

foreach ($n in $USER_FIRST_LAST_LIST) {
    if ([string]::IsNullOrWhiteSpace($n)) { continue }

    $parts = $n.Trim().Split(" ", 2)
    if ($parts.Count -lt 2) { continue }

    $first = $parts[0].Trim()
    $last  = $parts[1].Trim()
    
    $deptName = ($Departments.Keys | Get-Random)
    $dept = $Departments[$deptName]
    $title = $dept.Titles | Get-Random
    $description = "$($dept.Description) - $title"

    $username = "$($first.Substring(0,1))$last".ToLower()

    $OUPath = "OU=$deptName,OU=$BaseOUName,$DomainDN"

    try {
        if (Get-ADUser -Filter {SamAccountName -eq $username} -ErrorAction SilentlyContinue) {
            Write-Host "Already exists: $username" -ForegroundColor Yellow
            continue
        }

        $newUser = New-ADUser `
            -SamAccountName $username `
            -UserPrincipalName "$username@$((Get-ADDomain).DNSRoot)" `
            -AccountPassword $password `
            -GivenName $first `
            -Surname $last `
            -DisplayName "$first $last" `
            -Name "$first $last" `
            -Description $description `
            -Department $deptName `
            -Title $title `
            -EmployeeID $username `
            -Path $OUPath `
            -PasswordNeverExpires $true `
            -Enabled $true `
            -PassThru

        Add-ADGroupMember -Identity $deptName -Members $username

        $usersCreated += $newUser
        Write-Host "✓ $username → $first $last | $deptName | $title" -ForegroundColor Cyan
    }
    catch {
        Write-Host "✗ Failed $username : $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ====================== ASSIGN MANAGERS ======================
Write-Host "`nAssigning Managers..." -ForegroundColor Magenta

$managerCount = [math]::Max(1, [int]($usersCreated.Count * 0.15))  # ~15% managers

foreach ($deptName in $Departments.Keys) {
    $deptUsers = $usersCreated | Where-Object { $_.Department -eq $deptName }
    
    if ($deptUsers.Count -lt 2) { continue }

    # Select random managers for this department
    $managers = $deptUsers | Get-Random -Count ([math]::Min($managerCount, [int]($deptUsers.Count * 0.25)))
    
    foreach ($user in $deptUsers) {
        if ($managers.SamAccountName -contains $user.SamAccountName) { continue }  # Skip managers

        $manager = $managers | Get-Random
        if ($manager) {
            Set-ADUser -Identity $user -Manager $manager.DistinguishedName
        }
    }
}

# ====================== SUMMARY ======================
Write-Host "`n=== Creation Completed Successfully ===" -ForegroundColor Green
Write-Host "Total Users Created : $($usersCreated.Count)" -ForegroundColor Green
Write-Host "Departments         : $($Departments.Count)" -ForegroundColor Green
Write-Host "Password            : $PASSWORD_FOR_USERS" -ForegroundColor Yellow
Write-Host "`nYou can now view users in ADUC under OU=_USERS" -ForegroundColor Cyan
