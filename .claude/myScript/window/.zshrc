if [ -z "$INTELLIJ_ENVIRONMENT_READER" ] && [ "$TMUX" = "" ] && [ "$WARP_IS_LOCAL_SHELL_SESSION" = "" ]; then
  exec tmux
fi


# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:/usr/local/bin:$PATH:$HOME/.local/bin
export PATH=/usr/local/mongodb/bin:$PATH
export PATH="$PATH:$(npm config get prefix)/bin"
export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-nvm)

source $HOMEBREW_PREFIX/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

alias dcls="docker ps -a; docker network ls; docker images"
alias gdrop="git status; git add .; git stash; git stash drop"
alias gpushof="git push origin HEAD -f"
alias dcom="docker-compose"
alias gcom="git commit -m"
alias gpo="git push origin HEAD"
alias dc="docker"
alias mnkb="minikube"
alias kctl="kubectl"
alias hgrep="history | grep"
alias kbls="kubectl get deployments ; kubectl get pods; kubectl get services"

# uncommon alias but needed
alias gset="git remote set-url"
alias mongodpath="mongod --dbpath=/Users/danhtran/data/db"
alias p="pnpm"

# cli-ai alias
# source ~/.zshrc
cc() {
    local input="${1-}"

    # Windows-only: set TLS env var once at start
    if [[ "$OSTYPE" == msys* || "$OSTYPE" == mingw* || "$OSTYPE" == cygwin* ]]; then
        export NODE_TLS_REJECT_UNAUTHORIZED=0
    fi
    
    # No arg, or arg doesn't start with 'x' → passthrough
    [[ -z "$input" || "${input:0:1}" != "x" ]] && { claude "$@"; return; }

    local settings=""
    local skip=""

    # Count leading x's (x=1, xx=2, xxx=3…)
    local x_count=0
    for ((i=0; i<${#input}; i++)); do
        [[ "${input:$i:1}" == "x" ]] && ((++x_count)) || break
    done

    # xx+ (x_count >= 2) → skip permissions
    [[ $x_count -ge 2 ]] && skip="--allow-dangerously-skip-permissions"

    # Strip leading x's → remainder (z, l, or empty)
    local remainder="${input:$x_count}"

    # If remainder exists and matches a known env, use it
    case "$remainder" in
        z) settings="$HOME/.claude/env.glm.json" ;;
        l) settings="$HOME/.claude/env.longcat.json" ;;
        p) settings="$HOME/.claude/env.prox.json" ;;
    esac

    # Unknown remainder is ignored — the x-prefixed is "our" logic

    # Build args: strip the x-prefixed first arg, pass the rest
    local args=("${@:2}")

    if [[ -n "$settings" && -n "$skip" ]]; then
        claude $skip --settings "$settings" "${args[@]}"
    elif [[ -n "$settings" ]]; then
        claude --settings "$settings" "${args[@]}"
    else
        claude $skip "${args[@]}"
    fi
}

alias op='opencode'
alias ola='ollama'
alias olac='ollama launch --config'

# cd-custom
alias movi='cd ~/Movies'
alias cdno='cd ~/myData/noxidian'

# WORK_DEV
alias cdcc='cd ~/.claude'
alias cdnx='cd ~/dev/global'
alias cdbo='cd ~/dev/global/console-fe'
alias bots='pnpm --filter @gfe/scenario-console tsc:alpha'
alias gcmo='git commit --no-verify -m'
alias targit='tar -cf "${PWD##*/}$(date +%y%m%d).tar" --checkpoint=1000 --checkpoint-action=dot .git'

export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
export PUPPETEER_EXECUTABLE_PATH=`which chromium`
source /Users/danhtran/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# pnpm
export PNPM_HOME="/Users/danhtran/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
# __conda_setup="$('/opt/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
# if [ $? -eq 0 ]; then
#     eval "$__conda_setup"
# else
#     if [ -f "/opt/anaconda3/etc/profile.d/conda.sh" ]; then
#         . "/opt/anaconda3/etc/profile.d/conda.sh"
#     else
#         export PATH="/opt/anaconda3/bin:$PATH"
#     fi
# fi
# unset __conda_setup
# <<< conda initialize <<<


# Added by Antigravity
export PATH="/Users/danhtran/.antigravity/antigravity/bin:$PATH"
