# Some good standards, which are not used if the user
# creates his/her own .bashrc/.bash_profile

# --show-control-chars: help showing Korean or accented characters
alias ls='ls -F --color=auto --show-control-chars'
alias ll='ls -l'

# from git zsh plugin
alias g='git'
alias gcount='git shortlog --summary --numbered'
alias gco='git checkout'
alias gcp='git cherry-pick'
alias gcpa='git cherry-pick --abort'
alias gcpc='git cherry-pick --continue'
alias grb='git rebase'
alias grba='git rebase --abort'
alias grbc='git rebase --continue'
alias grbi='git rebase --interactive'
alias gc='git commit --verbose'
alias gc!='git commit --verbose --amend'
alias gcn!='git commit --verbose --no-edit --amend'
alias gcam='git commit --all --message'
alias gca!='git commit --verbose --all --amend'
alias gcan!='git commit --verbose --all --no-edit --amend'
alias gcans!='git commit --verbose --all --signoff --no-edit --amend'
alias gcsm='git commit --signoff --message'
alias gcas='git commit --all --signoff'
alias gcasm='git commit --all --signoff --message'
alias gcb='git checkout -b'
alias gcf='git config --list'
alias gstaa='git stash apply'
alias gstc='git stash clear'
alias gstd='git stash drop'
alias gstl='git stash list'
alias gstp='git stash pop'
alias gsta='git stash push'
alias gstu='gsta --include-untracked'
alias gstall='git stash --all'
alias grhh='git reset --hard'
alias gl='git pull'
alias gp='git push'
alias gup='git pull --rebase'
alias gupv='git pull --rebase --verbose'
alias gca='git commit --verbose --all'

alias gst='git status'
alias ga='git add'
alias gwt='git worktree'
alias gfa='git fetch --all --tags --prune --jobs=10'

# custom git command
alias gpo='git push origin HEAD'
alias gpf='git push origin HEAD -f'
alias gplo='git push lo HEAD'
alias gplof='git push origin HEAD -f'
alias gcm='git commit -m'
alias gcmo='git commit --no-verify -m'
alias gcmo!='git commit --verbose --all --no-edit --amend --no-verify'
alias gfoxx='git add . && git commit --verbose --all --no-edit --amend && git push origin HEAD -f'

alias gcn0!='git commit --verbose --no-edit --amend --no-verify'

# custom docker command
alias dcup='docker compose up -d'
alias dcdo='docker compose down'
alias dc='docker compose'
alias p='pnpm'

# window only
alias open='explorer'

# AI-CLI
alias tls='export NODE_TLS_REJECT_UNAUTHORIZED=0'
alias op='export NODE_TLS_REJECT_UNAUTHORIZED=0 && opencode'

# alias cc='export NODE_TLS_REJECT_UNAUTHORIZED=0 && claude'
# alias clm='export NODE_TLS_REJECT_UNAUTHORIZED=0 && claude --settings ~/.claude/glm.json'
# cli-ai alias
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
				o) settings="$HOME/.claude/env.openrouter.json" ;;
				d) settings="$HOME/.claude/env.devgo.json" ;;
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


alias ola='ollama'
alias olac='ollama launch --config'

# personal
alias cdcc='cd ~/.claude'
alias cdno='cd d:/myData/noxidian'
alias cdbo='cd ~/dev/global/scenario-console'
alias tsbo='pnpm --filter @gfe/scenario-console tsc:alpha'
alias bye='export ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_BASE_URL=http://localhost:11434 NODE_TLS_REJECT_UNAUTHORIZED=0'
alias bybo='export ANTHROPIC_AUTH_TOKEN=ollama ANTHROPIC_BASE_URL=http://localhost:11434 NODE_TLS_REJECT_UNAUTHORIZED=0 && cdbo'
alias targit='tar -cf "$(date +%y%m%d)_${PWD##*/}.tar" --checkpoint=1000 --checkpoint-action=dot .git'
alias info='du -sh'
alias git_clean='git reflog expire --expire=now --all && git gc --prune=now --aggressive'

case "$TERM" in
xterm*)
	# The following programs are known to require a Win32 Console
	# for interactive usage, therefore let's launch them through winpty
	# when run inside `mintty`.
	for name in node ipython php php5 psql python2.7 winget
	do
		case "$(type -p "$name".exe 2>/dev/null)" in
		''|/usr/bin/*) continue;;
		esac
		alias $name="winpty $name.exe"
	done
	;;
esac

case "$TERM" in
xterm*)
	# The following programs are known to require a Win32 Console
	# for interactive usage, therefore let's launch them through winpty
	# when run inside `mintty`.
	for name in node ipython php php5 psql python2.7 winget
	do
		case "$(type -p "$name".exe 2>/dev/null)" in
		''|/usr/bin/*) continue;;
		esac
		alias $name="winpty $name.exe"
	done
	;;
esac

tarful() {
  local BASE="$HOME/dev/global"
  local today=$(date +%y%m%d)

  _process_dir() {
	  local dir="$1"
	  echo "Processing $dir..."
	  (
		  cd "$BASE/$dir" 2>/dev/null || { echo "Failed to cd to $BASE/$dir"; return
1; }

		  # Run targit, ignore the warning error
		  targit 2>/dev/null || true

		  # Check if tar with today's date was created
		  local expected_tar="${today}_${dir}.tar"
		  if [[ -f "$expected_tar" ]]; then
			  mv "$expected_tar" "$BASE/"
			  echo "Moved $expected_tar to $BASE"
		  else
			  # Try to find any tar with today's prefix as fallback
			  local tar_file
			  tar_file=$(ls -t ${today}_*.tar 2>/dev/null | head -1)
			  if [[ -f "$tar_file" ]]; then
				  mv "$tar_file" "$BASE/"
				  echo "Moved $tar_file to $BASE"
			  else
				  echo "Warning: No tar file found for $dir"
				  return 1
			  fi
		  fi
	  )
  }

  _process_dir "scenario-console" || return 1
  _process_dir "scenario-console-admin-api" || return 1

  echo "Done! Tar files are in $BASE"
}