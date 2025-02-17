#!/usr/bin/env zsh

if [[ $- =~ i ]]; then

# -----------------------------------------------------------------------------
# utility function
# -----------------------------------------------------------------------------

# See http://unix.stackexchange.com/questions/101080/realpath-command-not-found
realpath ()
{
    f=$@;
    if [ -d "$f" ]; then
        base="";
        dir="$f";
    else
        base="/$(basename "$f")";
        dir=$(dirname "$f");
    fi;
    dir=$(cd "$dir" && /bin/pwd);
    echo "$dir$base"
}

# -----------------------------------------------------------------------------
# directory
# -----------------------------------------------------------------------------

# _fd - cd to selected directory
_fd() {
  local dir
  dir="$(
    find "${1:-.}" -path '*/\.*' -prune -o -type d -print 2> /dev/null \
      | fzf +m
  )" || return
  cd "$dir" || return
}

# _fdm - cd to selected directory (search depth is restricted by maxdepth)
_fdm() {
  local dir
  dir="$(
    find "${1:-.}" -path '*/\.*' -prune -o -type d -print -maxdepth 3 2> /dev/null \
      | fzf +m
  )" || return

  # Update fasd entries
  fasd -A "$dir"

  cd "$dir" || return
}

# _fda - including hidden directories
_fda() {
  local dir
  dir="$(
    find "${1:-.}" -type d 2> /dev/null \
      | fzf +m
  )" || return
  cd "$dir" || return
}

# _fdr - cd to selected parent directory
_fdr() {
  local dirs=()
  local parent_dir

  get_parent_dirs() {
    if [[ -d "$1" ]]; then dirs+=("$1"); else return; fi
    if [[ "$1" == '/' ]]; then
      for _dir in "${dirs[@]}"; do echo "$_dir"; done
    else
      get_parent_dirs "$(dirname "$1")"
    fi
  }

  parent_dir="$(
    get_parent_dirs "$(realpath "${1:-$PWD}")" \
      | fzf +m
  )" || return

  cd "$parent_dir" || return
}

# _fst - cd into the directory from stack
_fst() {
  local dir
  dir="$(
    dirs \
      | sed 's#\s#\n#g' \
      | uniq \
      | sed "s#^~#$HOME#" \
      | fzf +s +m -1 -q "$*"
  )"
  # $dirの存在を確かめないとCtrl-Cしたとき$HOMEにcdしてしまう
  if [[ -d "$dir" ]]; then
    cd "$dir" || return
  fi
}

# _cdf - cd into the directory of the selected file
_cdf() {
  local file
  file="$(fzf +m -q "$*")"
  cd "$(dirname "$file")" || return
}

# _zz - selectable cd to frecency directory
_zz() {
  local dir

  dir="$(
    fasd -dl \
      | fzf \
          --tac \
          --reverse \
          --select-1 \
          --no-sort \
          --no-multi \
          --tiebreak=index \
          --bind=ctrl-x:toggle-sort \
          --query "$*" \
      | grep -o '/.*'
  )" || return

  # Update fasd entries
  fasd -A "$dir"

  cd "$dir" || return
}

# zd - cd into selected directory with options
# The super function of _fd, _fda, _fdr, _fst, _cdf, _zz
zd() {
  read -r -d '' helptext <<EOF
usage: zd [OPTIONS]
  zd: cd to selected options below
OPTIONS:
  -d [path]: Directory (default)
  -a [path]: Directory included hidden
  -m [path]: Directory (limited search depth, currently 3 depth)
  -r [path]: Parent directory
  -s [query]: Directory from stack
  -f [query]: Directory of the selected file
  -z [query]: Frecency directory
  -h: Print this usage
EOF

  usage() {
    echo "$helptext"
  }

  if [[ -z "$1" ]]; then
    # no arg
    _fdm
  elif [[ "$1" == '..' ]]; then
    # arg is '..'
    shift
    _fdr "$1"
  elif [[ "$1" == '-' ]]; then
    # arg is '-'
    shift
    _fst "$*"
  elif [[ "${1:0:1}" != '-' ]]; then
    # first string is not -
    _fd "$(realpath "$1")"
  else
    # args is start from '-'
    while getopts darfszmh OPT; do
      case "$OPT" in
        d) shift; _fd  "$1";;
        a) shift; _fda "$1";;
        m) shift; _fdm  "$1";;
        r) shift; _fdr "$1";;
        s) shift; _fst "$*";;
        f) shift; _cdf "$*";;
        z) shift; _zz  "$*";;
        h) usage; return 0;;
        *) usage; return 1;;
      esac
    done
  fi
}


# -----------------------------------------------------------------------------
# file
# -----------------------------------------------------------------------------

# fe [FUZZY PATTERN] - Open the selected file with the default editor
#   - Bypass fuzzy finder if there's only one match (--select-1)
#   - Exit if there's no match (--exit-0)
fe() {
  local IFS=$'\n'
  local files=()
  files=(
    "$(fzf-tmux \
          --query="$1" \
          --multi \
          --select-1 \
          --exit-0
    )"
  ) || return
  "${EDITOR:-vim}" "${files[@]}"
}

# fo - Modified version of fe() where you can press
#   - CTRL-O to open with $OPENER,
#   - CTRL-E or Enter key to open with $EDITOR
fo() {
  local IFS=$'\n'
  local out=()
  local key
  local file

  out=(
    "$(
        fzf-tmux \
          --query="$1" \
          --exit-0 \
          --expect=ctrl-o,ctrl-e
    )"
  )
  key="$(head -1 <<< "${out[@]}")"
  file="$(head -2 <<< "${out[@]}" | tail -1)" || return

  if [[ "$key" == ctrl-o ]]; then
    "${OPENER:-xdg-open}" "$file"
  else
    "${EDITOR:-vim}" "$file"
  fi
}

# v - open files in ~/.viminfo
v() {
  local files
  files="$(
    grep '^>' "$HOME/.viminfo" \
      | cut -c3- \
      | while read -r line; do
          [[ -f "${line/\~/$HOME}" ]] && echo "$line"
        done \
      | fzf -m -0 -1 -q "$*"
  )"
  "${EDITOR:-vim}" "${files/\~/$HOME}"
}


# ALT-I - Paste the selected entry from locate output into the command line
fzf-locate-widget() {
  local selected
  if selected=$(locate / | fzf -q "$LBUFFER"); then
    LBUFFER=$selected
  fi
  zle redisplay
}
zle     -N    fzf-locate-widget
bindkey '\ei' fzf-locate-widget

fi


# fez - selectable edit frecency file
fez() {
  local file

  file="$(
    fasd -fl \
      | fzf \
          --tac \
          --reverse \
          --select-1 \
          --no-sort \
          --no-multi \
          --tiebreak=index \
          --bind=ctrl-x:toggle-sort \
          --query "$*" \
      | grep -o '/.*'
  )" || return

  # Update fasd entries
  fasd -A "$file"

  "${EDITOR:-vim}" "$file"
}


# -----------------------------------------------------------------------------
# git
# -----------------------------------------------------------------------------

# fbr - checkout git branch (including remote branches)
#   - sorted by most recent commit
#   - limit 30 last branches
fbr() {
  local branches
  local num_branches
  local branch
  local target

  branches="$(
    git for-each-ref \
      --count=30 \
      --sort=-committerdate \
      refs/heads/ \
      --format='%(refname:short)'
  )" || return

  branch="$(
    echo "$branches" \
      | fzf-tmux +m
  )" || return

  target="$(
    echo "$branch" \
      | sed "s/.* //" \
      | sed "s#remotes/[^/]*/##"
  )" || return

  git checkout "$target"
}

# fco - checkout git branch/tag
fco() {
  local tags
  local branches
  local target

  tags="$(
    git tag \
      | awk '{print "\x1b[31;1mtag\x1b[m\t" $1}'
  )" || return

  branches="$(
    git branch --all \
      | grep -v HEAD \
      | sed 's/.* //' \
      | sed 's#remotes/[^/]*/##' \
      | sort -u \
      | awk '{print "\x1b[34;1mbranch\x1b[m\t" $1}'
  )" || return

  target="$(
    printf '%s\n%s' "$tags" "$branches" \
      | fzf-tmux \
          -l40 \
          -- \
          --no-hscroll \
          --ansi \
          +m \
          -d '\t' \
          -n 2 \
          -1 \
          -q "$*"
  )" || return

  git checkout "$(echo "$target" | awk '{print $2}')"
}

# fcoc - checkout git commit
fcoc() {
  local commits
  local commit

  commits="$(
    git log --pretty=oneline --abbrev-commit --reverse
  )" || return

  commit="$(
    echo "$commits" \
      | fzf --tac +s +m -e
  )" || return

  git checkout "$(echo "$commit" | sed "s/ .*//")"
}

# fcs - get git commit sha
# example usage: git rebase -i "$(fcs)"
fcs() {
  local commits
  local commit

  commits="$(
    git log \
      --color=always \
      --pretty=oneline \
      --abbrev-commit \
      --reverse
  )" || return

  commit="$(
    echo "$commits" \
      | fzf \
          --tac \
          +s \
          +m \
          -e \
          --ansi \
          --reverse
  )" || return

  echo -n "$(echo "$commit" | sed "s/ .*//")"
}

# fshow - git commit browser
fshow() {
  local execute

  execute="grep -o \"[a-f0-9]\{7\}\" \
    | head -1 \
    | xargs -I % sh -c 'git show --color=always % | less -R'"

  git log \
    --graph \
    --color=always \
    --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" \
    | fzf \
        --ansi \
        --no-sort \
        --reverse \
        --tiebreak=index \
        --bind=ctrl-s:toggle-sort \
        --bind "ctrl-m:execute: ($execute) <<'FZF-EOF'
  {}
FZF-EOF"
}

# fstash - easier way to deal with stashes
# type fstash to get a list of your stashes
# enter shows you the contents of the stash
# ctrl-d shows a diff of the stash against your current HEAD
# ctrl-b checks the stash out as a branch, for easier merging
fstash() {
  local out
  local q
  local k
  local sha

  while out="$(
    git stash list --pretty='%C(yellow)%h %>(14)%Cgreen%cr %C(blue)%gs' \
      | fzf \
          --ansi \
          --no-sort \
          --query="$q" \
          --print-query \
          --expect=ctrl-d,ctrl-b
  )"; do
    q=$(head -1 <<< "$out")
    k=$(head -2 <<< "$out" | tail -1)
    sha=$(tail -1 <<< "$out" | cut -d' ' -f1)
    [[ -z "$sha" ]] && continue
    if [[ "$k" == 'ctrl-d' ]]; then
      git diff "$sha"
    elif [[ "$k" == 'ctrl-b' ]]; then
      git stash branch "stash-$sha" "$sha"
      break
    else
      git stash show -p "$sha"
    fi
  done
}

# fsquash = git squash (git-extras) combined with fcs
fsquash() {
  git squash $(fcs) "$1"
}

# fzf-gitlog-widget - git log browser
fzf-gitlog-widget() {
  local git_cmd
  local execute
  local fzf_cmd

  # %s: comment
  # %d: branch/tag
  # %h: hash
  # %cd: date
  # %an: author
  git_cmd='git log \
    --all \
    --graph \
    --date-order \
    --format=format:"%C(auto)%s %d %h %C(cyan)%cd %C(bold black)%an %C(auto)" \
    --date=short \
    --color=always'

  execute="grep -o '[a-f0-9]\{7\}' \
    | head -1 \
    | xargs -I % sh -c 'git show --color=always % | less -R'"

  fzf_cmd='fzf \
    --height=100% \
    --ansi \
    --reverse \
    --no-sort \
    --tiebreak=index \
    --bind=ctrl-x:toggle-sort'
  fzf_cmd="$fzf_cmd --bind \"ctrl-m:execute: ($execute) <<'FZF-EOF'
    {}
  FZF-EOF\""

  eval "$git_cmd | $fzf_cmd"
}

# fzf-gitlog-multi-widget - multi-selectable git show
#
# 1. Show `git log --graph`
# 2. Fuzzy Search
# 3. Select Tab key
# 4. Enter, then push selected commit message into STDOUT
#
# You can use pipe like below
# ```
# # Show only date
# fzf-gitlog-multi-widget | grep date
# # Commit message highlight 'hoge'
# fzf-gitlog-multi-widget | less -P 'hoge'
# ```
#
fzf-gitlog-multi-widget() {
  local git_cmd
  local fzf_cmd

  git_cmd='git log \
    --all \
    --graph \
    --date-order \
    --format=format:"%C(auto)%s %d %h %C(cyan)%cd %C(bold black)%an %C(auto)" \
    --date=short \
    --color=always'

  fzf_cmd='fzf \
    --height 100% \
    --multi \
    --ansi \
    --reverse \
    --no-sort \
    --tiebreak=index \
    --bind=ctrl-x:toggle-sort'

  eval "$git_cmd | $fzf_cmd" \
    | grep -o '[a-f0-9]\{7\}' \
    | xargs -I % sh -c 'git show % --color' \
    | cat
}



# -----------------------------------------------------------------------------
# pid
# -----------------------------------------------------------------------------

# fkill - kill process
fkill() {
  local pid

  pid="$(
    ps -ef \
      | sed 1d \
      | fzf -m \
      | awk '{print $2}'
  )" || return

  kill -"${1:-9}" "$pid"
}



# -----------------------------------------------------------------------------
# tmux
# -----------------------------------------------------------------------------

# fs [FUZZY PATTERN] - Select selected tmux session
#   - Bypass fuzzy finder if there's only one match (--select-1)
#   - Exit if there's no match (--exit-0)
fs() {
  local session

  session="$(
    tmux list-sessions -F "#{session_name}" \
      | fzf-tmux \
          --query="$1" \
          --select-1 \
          --exit-0
  )" || return

  tmux switch-client -t "$session"
}

# ftpane - switch pane (@george-b)
ftpane() {
  local panes
  local current_window
  local current_pane
  local target
  local target_window
  local target_pane

  panes="$(
    tmux list-panes \
      -s \
      -F '#I:#P - #{pane_current_path} #{pane_current_command}'
  )"
  current_pane="$(tmux display-message -p '#I:#P')"
  current_window="$(tmux display-message -p '#I')"

  target="$(
    echo "$panes" \
      | grep -v "$current_pane" \
      | fzf +m --reverse
  )" || return

  target_window="$(
    echo "$target" \
      | awk 'BEGIN{FS=":|-"} {print$1}'
  )"

  target_pane="$(
    echo "$target" \
      | awk 'BEGIN{FS=":|-"} {print$2}' \
      | cut -c 1
  )"

  if [[ "$current_window" -eq "$target_window" ]]; then
    tmux select-pane -t "$target_window.$target_pane"
  else
    tmux select-pane -t "$target_window.$target_pane" \
      && tmux select-window -t "$target_window"
  fi
}

# vim: set filetype=sh foldmethod=marker foldlevel=0:


# -----------------------------------------------------------------------------
# aliases
# -----------------------------------------------------------------------------
alias fd='zd'
