# ==============================================================================
# STRATEGY: INJECTING PLAINTEXT USER & ROUTING AUTOMATIC LOGINS
# ==============================================================================
$TinyTermPath  = "C:\Program Files (x86)\Century\TinyTERM\tt.exe"
$TemplateFile  = "C:\Automation\TinyTERM\term.emu"
$TemporaryTpx  = "C:\Automation\TinyTERM\runtime_session.tpx"

# Your variables to modify dynamically
$TargetHost    = "://dynamic-domain.com"
$TargetUser    = "my_ssh_username"
$TargetPass    = "MyDynamicSecret123!"

# Rebuild the file structure on the fly
(Get-Content -Path $TemplateFile) | ForEach-Object {
    if ($_ -like "node=*") {
        "node=$TargetHost"
    }
    # Securely write the plain username directly into the configuration text
    elseif ($_ -like "user=*") {
        "user=$TargetUser"
    }
    # Keep the password line completely blank
    elseif ($_ -like "password=*") {
        "password="
    }
    # Enforce automatic login macros to handle standard terminal prompts
    elseif ($_ -like "loginsw=*") {
        "loginsw=1" # Turns automated macros ON
    }
    elseif ($_ -like "loginW2=*") {
        "loginW2=assword:" # Waits for standard prompt string
    }
    elseif ($_ -like "loginS2=*") {
        # Sends a delay (^W), drops the string text, and appends a carriage return (^M)
        "loginS2=^W$TargetPass^M" 
    }
    else {
        $_
    }
} | Set-Content -Path $TemporaryTpx

# Launch the clean temporary configuration file natively
Start-Process -FilePath $TinyTermPath -ArgumentList "-t `"$TemporaryTpx`" -nosplash"
