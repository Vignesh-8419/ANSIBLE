# 1. Download the binary from your GitHub repository
wget -O /tmp/mt86plus https://raw.githubusercontent.com/Vignesh-8419/ANSIBLE/main/mt86plus

# 2. Create the target EFI directory
mkdir -p /boot/efi/EFI/memtest/

# 3. Move the binary and set permissions
mv /tmp/mt86plus /boot/efi/EFI/memtest/memtest.efi
chmod 755 /boot/efi/EFI/memtest/memtest.efi

# 4. Create a custom GRUB entry
# Using 'linux' command because your binary is identified as a bzImage
cat <<EOF > /etc/grub.d/40_custom
#!/bin/sh
exec tail -n +3 \$0

menuentry "MemTest86+ (Self-Compiled)" --class memtest86 {
    insmod part_gpt
    insmod fat
    search --no-floppy --fs-uuid --set=root $(lsblk -no UUID $(df /boot/efi | tail -1 | awk '{print $1}'))
    linux /EFI/memtest/memtest.efi
}
EOF

# 5. Make the custom script executable
chmod +x /etc/grub.d/40_custom

# 6. Update GRUB configuration
# On Rocky 9+, we target /boot/grub2/grub.cfg directly to avoid breaking the EFI stub
if [ -f /etc/rocky-release ] && grep -q "release 9" /etc/rocky-release; then
    grub2-mkconfig -o /boot/grub2/grub.cfg
else
    # For Rocky 8 or others, update both locations to be safe
    grub2-mkconfig -o /boot/grub2/grub.cfg
    grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg
fi
