# bash auto-completion script for standalone dap


_dap()
{
	local cur prev

	COMPREPLY=()
	cur=${COMP_WORDS[COMP_CWORD]}
	prev=${COMP_WORDS[COMP_CWORD-1]}

	#if [[ "$cur" == -* ]]; then
		COMPREPLY=( $( compgen -W '--help -h --add -a --remove -r --list -l --build -b --inspect -i --open -o --modify -m \
					--init --input-folder= --output-folder= --log-level=' -- $cur ) ) 
	#else
	#	_filedir
	#fi
}
complete -F _dap dap
