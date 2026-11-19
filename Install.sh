#!/data/data/com.termux/files/usr/bin/bash -e

VERSION=20250525
BASE_URL=https://kali.download/nethunter-images/current/rootfs
USERNAME=anand

red='\033[1;31m'
green='\033[1;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
light_cyan='\033[1;96m'
reset='\033[0m'

function unsupported_arch() {
    printf "${red}[*] Unsupported Architecture\n\n${reset}"
    exit 1
}

function ask() {
    while true; do
        if [ "${2:-}" = "Y" ]; then
            prompt="Y/n"
            default=Y
        elif [ "${2:-}" = "N" ]; then
            prompt="y/N"
            default=N
        else
            prompt="y/n"
            default=
        fi
        printf "${light_cyan}\n[?] "
        read -p "$1 [$prompt] " REPLY
        if [ -z "$REPLY" ]; then
            REPLY=$default
        fi
        printf "${reset}"
        case "$REPLY" in
            Y*|y*) return 0 ;;
            N*|n*) return 1 ;;
        esac
    done
}

function get_arch() {
    printf "${blue}[*] Checking device architecture ...${reset}\n"
    case $(getprop ro.product.cpu.abi) in
        arm64-v8a) SYS_ARCH=arm64 ;;
        armeabi|armeabi-v7a) SYS_ARCH=armhf ;;
        *) unsupported_arch ;;
    esac
}

function set_strings() {
    echo && echo ""
    if [[ ${SYS_ARCH} == "arm64" ]]; then
        echo "[1] Anand ARM64 (full)"
        echo "[2] Anand ARM64 (minimal)"
        echo "[3] Anand ARM64 (nano)"
        read -p "Enter the image you want to install: " wimg
        case $wimg in
            1) wimg="full" ;;
            2) wimg="minimal" ;;
            3) wimg="nano" ;;
            *) wimg="full" ;;
        esac
    elif [[ ${SYS_ARCH} == "armhf" ]]; then
        echo "[1] Anand ARMhf (full)"
        echo "[2] Anand ARMhf (minimal)"
        echo "[3] Anand ARMhf (nano)"
        read -p "Enter the image you want to install: " wimg
        case $wimg in
            1) wimg="full" ;;
            2) wimg="minimal" ;;
            3) wimg="nano" ;;
            *) wimg="full" ;;
        esac
    fi
    CHROOT=anand-${SYS_ARCH}
    IMAGE_NAME=kali-nethunter-rootfs-${wimg}-${SYS_ARCH}.tar.xz
    SHA_NAME=${IMAGE_NAME}.sha512sum
}

function prepare_fs() {
    unset KEEP_CHROOT
    if [ -d "${CHROOT}" ]; then
        if ask "Existing rootfs directory found. Delete and create a new one?" "N"; then
            rm -rf "${CHROOT}"
        else
            KEEP_CHROOT=1
        fi
    fi
}

function cleanup() {
    if [ -f "${IMAGE_NAME}" ]; then
        if ask "Delete downloaded rootfs file?" "N"; then
            rm -f "${IMAGE_NAME}"
            rm -f "${SHA_NAME}"
        fi
    fi
}

function check_dependencies() {
    printf "${blue}\n[*] Checking package dependencies...${reset}\n"
    apt update -y &> /dev/null
    REQUIRED_PACKAGES=("proot" "tar" "axel" "xz-utils")
    for PACKAGE_NAME in "${REQUIRED_PACKAGES[@]}"; do
        if dpkg -s "$PACKAGE_NAME" &> /dev/null; then
            echo " $PACKAGE_NAME is OK"
        else
            printf " Installing ${PACKAGE_NAME}...\n"
            apt install -y "$PACKAGE_NAME" || {
                printf "${red}ERROR: Failed to install ${PACKAGE_NAME}.\n Exiting.\n${reset}"
                exit 1
            }
        fi
    done
    apt upgrade -y
}

function get_url() {
    ROOTFS_URL="${BASE_URL}/${IMAGE_NAME}"
    SHA_URL="${BASE_URL}/${SHA_NAME}"
}

function get_rootfs() {
    unset KEEP_IMAGE
    if [ -f "${IMAGE_NAME}" ]; then
        if ask "Existing image file found. Delete and download a new one?" "N"; then
            rm -f "${IMAGE_NAME}"
        else
            printf "${yellow}[!] Using existing rootfs archive${reset}\n"
            KEEP_IMAGE=1
            return
        fi
    fi
    printf "${blue}[*] Downloading rootfs...${reset}\n\n"
    get_url
    axel -o "${IMAGE_NAME}" "${ROOTFS_URL}" || wget --continue "${ROOTFS_URL}"
}

function verify_sha() {
    if [ -z "${KEEP_IMAGE:-}" ]; then
        printf "\n${blue}[*] Verifying integrity of rootfs...${reset}\n\n"
        if [ -f "${SHA_NAME}" ]; then
            sha512sum -c "$SHA_NAME" 2>/dev/null || {
                printf "${red} Rootfs corrupted. Please run this installer again\n${reset}"
                exit 1
            }
        else
            echo "[!] SHA file not found. Skipping verification..."
        fi
    fi
}

function get_sha() {
    if [ -z "${KEEP_IMAGE:-}" ]; then
        printf "\n${blue}[*] Getting SHA ... ${reset}\n\n"
        get_url
        if [ -f "${SHA_NAME}" ]; then
            rm -f "${SHA_NAME}"
        fi
        if curl --output /dev/null --silent --head --fail "${SHA_URL}"; then
            wget --continue "${SHA_URL}"
            verify_sha
        else
            echo "[!] SHA_URL does not exist. Skipping download."
        fi
    fi
}

function extract_rootfs() {
    if [ -z "${KEEP_CHROOT:-}" ]; then
        printf "\n${blue}[*] Extracting rootfs... ${reset}\n\n"
        proot --link2symlink tar -xf "$IMAGE_NAME" 2> /dev/null || :
    else
        printf "${yellow}[!] Using existing rootfs directory${reset}\n"
    fi
}

function create_launcher() {
    NH_LAUNCHER=${PREFIX}/bin/anand
    NH_SHORTCUT=${PREFIX}/bin/nh
    AN_SHORTCUT=${PREFIX}/bin/an
    cat > "$NH_LAUNCHER" <<- EOF
#!/data/data/com.termux/files/usr/bin/bash -e
cd \${HOME}
unset LD_PRELOAD
if [ ! -f "${HOME}/${CHROOT}/root/.version" ]; then
    touch "${HOME}/${CHROOT}/root/.version"
fi
user="$USERNAME"
home="/home/\$user"
start="sudo -u $USERNAME /bin/bash"
if ! grep -q "^$USERNAME:" "${HOME}/${CHROOT}/etc/passwd" 2>/dev/null || [[ "\$#" != "0" && ("\$1" == "-r" || "\$1" == "-R") ]]; then
    user="root"
    home="/\$user"
    start="/bin/bash --login"
    if [[ "\$#" != "0" && ("\$1" == "-r" || "\$1" == "-R") ]]; then
        shift
    fi
fi
RED_PS1='\[\033[1;31m\]anand@anand:\w\$\[\033[0m\] '
cmdline="proot \\
    --link2symlink \\
    -0 \\
    -r ${HOME}/${CHROOT} \\
    -b /dev \\
    -b /proc \\
    -b /sdcard \\
    -b ${HOME}/${CHROOT}\$home:/dev/shm \\
    -w \$home \\
    /usr/bin/env -i \\
    HOME=\$home \\
    HOSTNAME=anand \\
    PS1=\"\$RED_PS1\" \\
    PATH=/usr/local/sbin:/usr/local/bin:/bin:/usr/bin:/sbin:/usr/sbin \\
    TERM=\$TERM \\
    LANG=C.UTF-8 \\
    \$start"
cmd="\$@"
if [ "\$#" == "0" ]; then
    exec \$cmdline
else
    \$cmdline -c "\$cmd"
fi
EOF
    chmod 700 "$NH_LAUNCHER"
    ln -sf "${NH_LAUNCHER}" "${NH_SHORTCUT}"
    ln -sf "${NH_LAUNCHER}" "${AN_SHORTCUT}"
}

function create_kex_launcher() {
    KEX_LAUNCHER=${CHROOT}/usr/bin/kex
    mkdir -p "$(dirname "$KEX_LAUNCHER")"
    cat > "$KEX_LAUNCHER" <<- 'EOF'
#!/bin/bash
function start-kex() {
    if [ ! -f ~/.vnc/passwd ]; then
        passwd-kex
    fi
    USR=$(whoami)
    SCREEN=":1"
    [ "$USR" = "root" ] && SCREEN=":2"
    export USER="$USR"
    vncserver "$SCREEN" -localhost no
}
function stop-kex() {
    vncserver -kill :1 2>/dev/null
    vncserver -kill :2 2>/dev/null
}
function passwd-kex() {
    vncpasswd
}
function status-kex() {
    vncserver -list
}
case "$1" in
    start) start-kex ;;
    stop) stop-kex ;;
    status) status-kex ;;
    passwd) passwd-kex ;;
    *) start-kex; status-kex ;;
esac
EOF
    chmod 700 "$KEX_LAUNCHER"
}

function fix_profile_bash() {
    if [ -f "${CHROOT}/root/.bash_profile" ]; then
        sed -i '/if/,/fi/d' "${CHROOT}/root/.bash_profile"
    fi
}

function fix_sudo() {
    chmod +s "${CHROOT}/usr/bin/sudo" 2>/dev/null || :
    chmod +s "${CHROOT}/usr/bin/su" 2>/dev/null || :
    mkdir -p "${CHROOT}/etc/sudoers.d"
    echo "${USERNAME} ALL=(ALL:ALL) ALL" > "${CHROOT}/etc/sudoers.d/${USERNAME}" 2>/dev/null || :
    echo "Set disable_coredump false" > "${CHROOT}/etc/sudo.conf" 2>/dev/null || :
}

function fix_uid() {
    USRID=$(id -u)
    GRPID=$(id -g)
    anand -r usermod -u "$USRID" "$USERNAME" 2>/dev/null || :
    anand -r groupmod -g "$GRPID" "$USERNAME" 2>/dev/null || :
}

function configure_prompt_and_hostname() {
    echo "anand" > "${CHROOT}/etc/hostname" 2>/dev/null || :
    PROMPT_SNIPPET='export PS1="\[\033[1;31m\]anand@anand:\w\$\[\033[0m\] "'

    if [ -f "${CHROOT}/root/.bashrc" ]; then
        grep -q "anand@anand" "${CHROOT}/root/.bashrc" || printf "\n%s\n" "$PROMPT_SNIPPET" >> "${CHROOT}/root/.bashrc"
    fi
    if [ -f "${CHROOT}/root/.bash_profile" ]; then
        grep -q "anand@anand" "${CHROOT}/root/.bash_profile" || printf "\n%s\n" "$PROMPT_SNIPPET" >> "${CHROOT}/root/.bash_profile"
    fi

    if [ -d "${CHROOT}/home/${USERNAME}" ]; then
        touch "${CHROOT}/home/${USERNAME}/.bashrc"
        grep -q "anand@anand" "${CHROOT}/home/${USERNAME}/.bashrc" || printf "\n%s\n" "$PROMPT_SNIPPET" >> "${CHROOT}/home/${USERNAME}/.bashrc"
        chown -R 1000:1000 "${CHROOT}/home/${USERNAME}" 2>/dev/null || :
    fi
}

function print_banner() {
    clear
    printf "${red}####################################################################\n"
    printf "${red}##                                                                ##\n"
    printf "${red}##     db      888b      88    db    888b      88 88888888ba,     ##\n"
    printf "${red}##    d88b     8888b     88   d88b   8888b     88 88      \`\"8b    ##\n"
    printf "${red}##   d8''8b    88 '8b    88  d8''8b  88 '8b    88 88        \`8b   ##\n"
    printf "${red}##  d8'  '8b   88  '8b   88 d8'  '8b 88  '8b   88 88         88   ##\n"
    printf "${red}## d8YaaaaY8b  88   '8b  88d8YaaaaY8b88   '8b  88 88         88   ##\n"
    printf "${red}##d8''''''''8b 88    '8b 888''''''''888    '8b 88 88         8P   ##\n"
    printf "${red}##d8'        '8b88     '8888'        '8b     '888 88      .a8P    ##\n"
    printf "${red}##d8'          '88      '888'          '8b     '8 88888888Y\"'     ##\n"
    printf "${red}##                                                                ##\n"
    printf "${red}#### #######################    ANAND    #########################${reset}\n\n"
}

cd "$HOME"
print_banner
get_arch
set_strings
prepare_fs
check_dependencies
get_rootfs
get_sha
extract_rootfs
create_launcher
cleanup
printf "\n${blue}[*] Configuring Anand for Termux ...\n"
fix_profile_bash
fix_sudo
create_kex_launcher
fix_uid
configure_prompt_and_hostname
print_banner
printf "${green}[=] Anand for Termux installed successfully${reset}\n\n"
printf "${green}[+] To start Anand, type:${reset}\n"
printf "${green}[+] anand # To start Anand CLI${reset}\n"
printf "${green}[+] anand kex passwd # To set the KeX password${reset}\n"
printf "${green}[+] anand kex start # To start Anand GUI${reset}\n"
printf "${green}[+] anand kex stop # To stop Anand GUI${reset}\n"
printf "${green}[+] anand -r # To run Anand as root${reset}\n"
printf "${green}[+] nh or an # Shortcut for anand${reset}\n\n"
