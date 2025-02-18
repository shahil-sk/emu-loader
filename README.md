### **Frida Setup for Genymotion & Magisk-Based Android Pentesting**  
This repository contains a **Bash automation script** to set up **Frida-Server** on an Android emulator (Genymotion). It ensures a seamless **rooted testing environment** by:  

✅ **Starting Genymotion Emulator**  
✅ **Enabling ADB & Magisk Root Access**  
✅ **Configuring Burp Suite Proxy** 
(Burp Certificate You have to install it manually)
✅ **Detecting Device Architecture**  
✅ **Managing Frida-Server Versions** 
(Auto-Update & Push to Device)  
✅ **Starting & Verifying Frida-Server**  

## Note: in the script make sure add the path of genymotion gmtool to "GMTOOL" variable

### **Requirements**  
- Linux (Tested on Ubuntu)
- ADB  
- Genymotion installed  
- Frida tools (`frida`, `frida-server`)  will be installed automatically dw

### **Usage**  
Run the script to automate the Frida setup:  
```bash
chmod +x emu-loader.sh
./emu-loader.sh
```  

### **Features in Progress**   
🔹 Automating Frida injection into Magisk-based apps  
🔹 Additional debugging & logging  

written by @shahil_s_k
