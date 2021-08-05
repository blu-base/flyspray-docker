#!/usr/bin/bash
set -eo pipefail

declare -A php_version=(
	[default]='7.4'
)

declare -A cmd=(
	[apache]='apache2-foreground'
)

declare -A base=(
	[apache]='debian'
)

declare -A extras=(
	[apache]='\nRUN a2enmod headers rewrite remoteip ;\\\n    {\\\n     echo RemoteIPHeader X-Real-IP ;\\\n     echo RemoteIPTrustedProxy 10.0.0.0/8 ;\\\n     echo RemoteIPTrustedProxy 172.16.0.0/12 ;\\\n     echo RemoteIPTrustedProxy 192.168.0.0/16 ;\\\n    } > /etc/apache2/conf-available/remoteip.conf;\\\n    a2enconf remoteip'

)

declare -A crontab_int=(
	[default]='5'
)

variants=(
	apache
)

min_version='1.0-rc10'

function create_variant() {
	dir="$1/$variant"
	phpVersion=${php_version[$version]-${php_version[default]}}
	crontabInt=${crontab_int[$version]-${crontab_int[default]}}

	# create the version+variant directory with a Dockerfile
	mkdir -p "$dir"

	template="Dockerfile-${base[$variant]}.template"
	echo "# DO NOT EDIT: created by update.sh from $template" > "$dir/Dockerfile"
	cat "$template" > "$dir/Dockerfile"

	echo "updating $2 [$1] $variant"

	# replace the variables
	sed -ri -e '
		s/%%PHP_VERSION%%/'"$phpVersion"'/g;
		s/%%VARIANT%%/'"$variant"'/g;
		s/%%VERSION%%/'"$1"'/g;
		s/%%FULLVERSION%%/'"$2"'/g;
		s/%%BASE_DOWNLOAD_URL%%/'"$3"'/g;
		s/%%CMD%%/'"${cmd[$variant]}"'/g;
		s|%%VARIANT_EXTRAS%%|'"${extras[$variant]}"'|g;
		s/%%CRONTAB_INT%%/'"$crontabInt"'/g;
	' "$dir/Dockerfile"

	case "$phpVersion" in
		7.4 )
			# sed
			;;
	esac

	# copy the shell scripts
	for name in entrypoint cron; do
		cp "docker-$name.sh" "$dir/$name.sh"
	done

	# copy the upgrade.exclude 
	cp upgrade.exclude "$dir/"

	# Copy the config directory
	cp -rT .config "$dir/config"

	# Remove Apache config if we're not an Apache variant.
	if [ "$variant" != "apache" ]; then
		rm "$dir/config/apache-pretty-urls.config.php"
	fi
}

curl -fsSL 'https://api.github.com/repos/flyspray/flyspray/releases/latest' | \
  jq .tag_name > latest.txt

find . -maxdepth 1 -type d -regextype sed -regex '\./[[:digit:]]\+\.[[:digit:]]\+\(-rc[[:digit:]]*\)\?' -exec rm -r '{}' \;

fullversions=( $(curl -fsSL 'https://api.github.com/repos/flyspray/flyspray/releases' | jq .[].tag_name | sed 's/"\(.*\)"/\1/g' ) )

versions=( $( printf '%s\n' "${fullversions[@]:0:3}" | sed 's/v\(.*\)/\1/g' ) )

for version in "${versions[@]}"; do
  fullversion="$( printf '%s\n' "${fullversions[@]}" | grep -E "$version" | head -1 )"
  for variant in "${variants[@]}"; do
    create_variant "$version" "$fullversion" "https:\/\/github.com\/Flyspray\/flyspray"
  done
done
