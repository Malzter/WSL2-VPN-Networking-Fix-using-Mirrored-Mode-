
```markdown
# WSL2 VPN Networking Fix (using Mirrored Mode)

## Problem

A common issue faced by Windows Subsystem for Linux (WSL2) users is the loss of internet connectivity within the WSL distribution when a Virtual Private Network (VPN) is connected on the Windows host machine.

This often manifests with error messages during WSL startup like:
```
wsl: Failed to configure network (networkingMode Nat), falling back to networkingMode VirtioProxy.
```
The default NAT networking mode in WSL2 can conflict with how VPN clients alter the network stack on Windows, preventing WSL from properly establishing its network connection and resolving DNS addresses.

## Solution

This repository provides a simple PowerShell script that automates a known workaround for this issue. The workaround involves:

1.  Configuring WSL2 to use the `mirrored` networking mode (available and recommended on Windows 11 version 22H2 and later) via the `.wslconfig` file. This mode often has better compatibility with Windows networking, including VPNs.
2.  Disabling WSL's automatic generation of `/etc/resolv.conf` in your Linux distribution via the `/etc/wsl.conf` file.
3.  Creating a static `/etc/resolv.conf` file in your WSL distribution with manually specified DNS servers (like a public DNS or potentially your VPN's DNS).
4.  Making the `/etc/resolv.conf` file immutable to prevent it from being overwritten.

This setup ensures that your WSL distribution uses a more compatible networking mode and relies on stable DNS servers that are accessible even with your VPN active.

## Prerequisites

Before running the script, ensure you have the following:

* **Windows 11:** The `networkingMode=mirrored` setting is primarily supported and recommended on Windows 11 (version 22H2 or later). While the script might run on Windows 10, the `mirrored` mode benefit is specific to Windows 11.
* **WSL2 Installed and Setup:** You have WSL2 installed and your desired Linux distribution (e.g., Ubuntu) is set to run as WSL2 (`wsl --list --verbose` will show version 2).
* **Administrative Privileges:** The script modifies system-level settings and shuts down WSL, requiring you to run PowerShell as an Administrator.
* **Default WSL Distribution:** The script operates on your *default* WSL distribution. If you have multiple distributions, set the desired one as default using `wsl --set-default <DistributionName>`.

## How to Use

1.  **Clone or Download:** Get the contents of this repository to your Windows machine. You can clone it using Git or download the ZIP file.
    ```bash
    git clone [https://github.com/YourUsername/wsl-vpn-networking-fix.git](https://github.com/YourUsername/wsl-vpn-networking-fix.git)
    ```
    (Replace `YourUsername` with your GitHub username)
2.  **Open PowerShell as Administrator:** Search for "PowerShell" in the Windows search bar, right-click on "Windows PowerShell" or "PowerShell", and select "Run as administrator".
3.  **Navigate to the Script Directory:** Use the `cd` command to change your current directory to where you saved the script.
    ```powershell
    cd path\to\wsl-vpn-networking-fix
    ```
4.  **Run the Script:** Execute the PowerShell script.
    ```powershell
    ./setup-wsl-networking.ps1
    ```
5.  **Follow the Prompts:** The script will guide you through the process. It will configure files, shut down WSL, and then **prompt you to manually open your WSL distribution**. Open your WSL terminal, wait for it to load, and then press Enter back in the PowerShell script to allow it to complete the `resolv.conf` configuration.

## What the Script Does

The `setup-wsl-networking.ps1` script performs the following actions:

1.  **Configures `.wslconfig`:** Modifies or creates the `.wslconfig` file in your Windows user profile (`C:\Users\YourUsername\.wslconfig`) to add or ensure the `[wsl2]` section contains `networkingMode=mirrored`.
2.  **Configures `/etc/wsl.conf`:** Executes commands inside your default WSL distribution to modify or create the `/etc/wsl.conf` file. It adds or ensures the `[network]` section contains `generateResolvConf=false`. This tells WSL not to automatically manage `/etc/resolv.conf`.
3.  **Shuts Down WSL:** Runs `wsl --shutdown` from PowerShell to completely stop all running WSL instances, applying the changes made to `.wslconfig` and `/etc/wsl.conf`.
4.  **Removes Old `resolv.conf`:** After you restart your WSL instance and press Enter in the script, it runs `sudo rm -f /etc/resolv.conf` inside WSL to remove any existing `resolv.conf` file or symbolic link (which might be pointing to a dynamic file managed by `systemd-resolved`).
5.  **Creates New `resolv.conf`:** Creates a new, static `/etc/resolv.conf` file inside WSL with the specified `nameserver` entry. By default, it uses Google Public DNS (`8.8.8.8`).
6.  **Makes `resolv.conf` Immutable:** Runs `sudo chattr +i /etc/resolv.conf` inside WSL to set the immutable attribute, preventing accidental modification or unwanted changes by other processes.

## Customizing the DNS Server

By default, the script uses `nameserver 8.8.8.8`. If you want to use a different DNS server (e.g., Cloudflare's 1.1.1.1, your VPN's specific DNS server, or your router's IP), you can edit the `setup-wsl-networking.ps1` file before running it.

Change the line:
```powershell
$nameserver = "8.8.8.8"
```
to your desired IP address, for example:
```powershell
$nameserver = "1.1.1.1"
```

## Verification

After the script completes and you have restarted your WSL instance, you can verify the fix:

1.  **Check Networking Mode:** Open PowerShell and run `wsl --status`. Look for `Networking Mode: mirrored`.
2.  **Check `resolv.conf`:** Open your WSL terminal and run `cat /etc/resolv.conf`. It should show only the `nameserver` line(s) you configured, without the automatic generation comments. Also, check its attributes with `lsattr /etc/resolv.conf`; you should see an `i` flag (`----i---------------`).
3.  **Test Connectivity:** With your VPN connected on Windows, try pinging a website from your WSL terminal: `ping google.com`. It should resolve the IP and show successful pings.

## Reverting Changes

If you need to undo the changes made by this script:

1.  **Remove Immutable Attribute (WSL):** Open your WSL terminal and run `sudo chattr -i /etc/resolv.conf`.
2.  **Delete `resolv.conf` (WSL):** `sudo rm /etc/resolv.conf`.
3.  **Remove/Edit `.wslconfig` (Windows):** Open `C:\Users\YourUsername\.wslconfig` in a text editor (run as administrator). Remove the `[wsl2]` section and the `networkingMode=mirrored` line. If you had other settings in `[wsl2]`, just remove the `networkingMode` line.
4.  **Remove/Edit `/etc/wsl.conf` (WSL):** Open your WSL terminal and run `sudo nano /etc/wsl.conf`. Remove the `[network]` section and the `generateResolvConf=false` line. If you had other settings in `[network]`, just remove the `generateResolvConf` line.
5.  **Shut Down WSL:** Open PowerShell and run `wsl --shutdown`.
6.  **Restart WSL:** Open your WSL instance. WSL will now revert to its default networking behavior and automatically generate a new `resolv.conf`.

## Troubleshooting (Brief)

* If the error persists, ensure your Windows and WSL are fully up to date (`wsl --update` and check Windows Updates).
* Confirm that no other software (especially VPNs, firewalls, or virtualization tools) is interfering with the WSL virtual network adapter. Temporarily disabling them one by one can help diagnose.
* Consider performing a Windows network reset (`netcfg -d` in an elevated Command Prompt/PowerShell, followed by a restart) as a last resort (note this will reset all network adapters and configurations).

## License

This project is licensed under the MIT License - see the LICENSE file for details (You would need to add an MIT license file to the repo).
```

Remember to replace `"https://github.com/YourUsername/wsl-vpn-networking-fix.git"` with the actual URL of your repository once you create it. You'll also need to create an `LICENSE` file if you choose the MIT license.

This README is comprehensive and should give users a clear understanding of the problem, the solution, and how to use your script effectively. Good luck with the repository!
