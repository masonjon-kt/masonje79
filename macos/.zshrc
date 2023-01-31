export http_proxy="http://127.0.0.1:3128/"
export https_proxy=$http_proxy
export ftp_proxy=$http_proxy
export rsync_proxy=$http_proxy
export HTTP_PROXY=$http_proxy
export HTTPS_PROXY=$http_proxy
export FTP_PROXY=$http_proxy
export RSYNC_PROXY=$http_proxy

alias ll='ls -lah'

export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
export JAVA_HOME=/Library/Java/JavaVirtualMachines/adoptopenjdk-8.jdk/Contents/Home


export NVM_DIR=~/.nvm
source $(brew --prefix nvm)/nvm.sh


function findword(){
	find . -type f -exec grep -i $1 {} +
}

function intellij(){
	open -na "IntelliJ IDEA.app" --args "$@"
}

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
