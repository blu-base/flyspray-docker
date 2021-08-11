#!/bin/sh

# version_greater A B returns whether A > B
version_greater() {
	[ "$(printf '%s\n' "$@" | sort | head -n 1)" != "$1" ]
}

# return true if specified directory is empty
directory_empty() {
	[ -z "$(ls -A "$1/")" ]
}


run_as() {
	if [ "$(id -u)" = 0 ]; then
		su -p www-data -s /bin/sh -c "$1"
	else
		sh -c "$1"
	fi
}

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	local varValue=$(env | grep -E "^${var}=" | sed -E -e "s/^${var}=//")
	local fileVarValue=$(env | grep -E "^${fileVar}=" | sed -E -e "s/^${fileVar}=//")
	if [ -n "${varValue}" ] && [ -n "${fileVarValue}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	if [ -n "${varValue}" ]; then
		export "$var"="${varValue}"
	elif [ -n "${fileVarValue}" ]; then
		export "$var"="$(cat "${fileVarValue}")"
	elif [ -n "${def}" ]; then
		export "$var"="$def"
	fi
	unset "$fileVar"
}



if expr "$1" : "apache" 1>/dev/null; then
	if [ -n "${APACHE_DISABLE_REWRITE_IP+x}" ]; then
		a2disconf remoteip
	fi
fi

if expr "$1" : "apache" 1>/dev/null || [ "$1" = "php-fpm" ] || [ "${FLYSPRAY_UPDATE:-0}" -eq 1 ]; then
#    if [ -n "${REDIS_HOST+x}" ]; then
#
#        echo "Configuring Redis as session handler"
#        {
#            file_env REDIS_HOST_PASSWORD
#            echo 'session.save_handler = redis'
#            # check if redis host is an unix socket path
#            if [ "$(echo "$REDIS_HOST" | cut -c1-1)" = "/" ]; then
#              if [ -n "${REDIS_HOST_PASSWORD+x}" ]; then
#                echo "session.save_path = \"unix://${REDIS_HOST}?auth=${REDIS_HOST_PASSWORD}\""
#              else
#                echo "session.save_path = \"unix://${REDIS_HOST}\""
#              fi
#            # check if redis password has been set
#            elif [ -n "${REDIS_HOST_PASSWORD+x}" ]; then
#                echo "session.save_path = \"tcp://${REDIS_HOST}:${REDIS_HOST_PORT:=6379}?auth=${REDIS_HOST_PASSWORD}\""
#            else
#                echo "session.save_path = \"tcp://${REDIS_HOST}:${REDIS_HOST_PORT:=6379}\""
#            fi
#            echo "redis.session.locking_enabled = 1"
#            echo "redis.session.lock_retries = -1"
#            # redis.session.lock_wait_time is specified in microseconds.
#            # Wait 10ms before retrying the lock rather than the default 2ms.
#            echo "redis.session.lock_wait_time = 10000"
#        } > /usr/local/etc/php/conf.d/redis-session.ini
#    fi

	installed_version="0.0"
	if [ -f /var/www/html/includes/class.flyspray.php ]; then
		installed_version=$(grep -E '\$version =' includes/class.flyspray.php | grep -oE "'.*'" | sed "s/'\(.*\)'/\1/g")
	fi

	image_version=$(grep -E '\$version =' /usr/src/flyspray/includes/class.flyspray.php | grep -oE "'.*'" | sed "s/'\(.*\)'/\1/g")

	if version_greater "$installed_version" "$image_version"; then
		echo "Can't start Flyspray because the version of the data ($installed_version) is higher than the docker image version ($image_version) and downgrading is not supported. Are you sure you have pulled the newest image version?"
		exit 1
	fi

	if version_greater "$image_version" "$installed_version"; then
		echo "Initializing flyspray $image_version ..."
		if [ "$installed_version" != "0.0" ]; then
			echo "Upgrading flyspray from $installed_version ..."
			# run_as 'php /var/www/html/occ app:list' | sed -n "/Enabled:/,/Disabled:/p" > /tmp/list_before
		fi

		if [ "$(id -u)" = 0 ]; then
			rsync_options="-rlDog --chown www-data:root"
		else
			rsync_options="-rlD"
		fi

		rsync $rsync_options --delete --exclude-from=/upgrade.exclude /usr/src/flyspray/ /var/www/html/

		for dir in attachements data fonts avatars themes vendor; do
			if [ ! -d "/var/www/html/$dir" ] || directory_empty "/var/www/html/$dir"; then
				rsync $rsync_options --include "/$dir/" --exclude '/*' /usr/src/flyspray/ /var/www/html/
			fi
		done

		# use profided .htaccess if apache is used
		if expr "$1" : "apache" 1>/dev/null; then
			if [ -f "/var/www/html/htaccess.dist" ]; then
				mv "/var/www/html/htaccess.dist" "/var/www/html/.htaccess"
			fi
		fi

		echo "Initializing finished"

		##install
		#if [ "$installed_version" = "0.0" ]; then
		#	echo "New flyspray instance"

		#	file_env MYSQL_HOST
		#	file_env MYSQL_DATABASE
		#	file_env MYSQL_PASSWORD
		#	file_env MYSQL_USER
		#	file_env POSTGRES_HOST
		#	file_env POSTGRES_DB
		#	file_env POSTGRES_PASSWORD
		#	file_env POSTGRES_USER

		#	CONF="/var/www/html/flyspray.conf.php"
		#	touch "$CONF"
		#	chmod 644 "$CONF"
		#	chown www-data "$CONF"
		#	
		#	echo "; <?php die( 'Do not access this page directly.' ); ?>\n" >> "$CONF"

		#	echo "[database]" >> "$CONF"


		#	if [ -n "${MYSQL_DATABASE+x}" ] && [ -n "${MYSQL_USER+x}" ] && [ -n "${MYSQL_PASSWORD+x}" ] && [ -n "${MYSQL_HOST+x}" ]; then
		#		echo "dbtype = \"mysqli\"" >> "$CONF"
		#		echo "dbhost = \"$MYSQL_HOST\"" >> "$CONF"
		#		echo "dbname = \"$MYSQL_DATABASE\"" >> "$CONF"
		#		echo "dbuser = \"$MYSQL_USER\"" >> "$CONF"
		#		echo "dbpass = \"$MYSQL_PASSWORD\"" >> "$CONF"
		#	elif [ -n "${POSTGRES_DB+x}" ] && [ -n "${POSTGRES_USER+x}" ] && [ -n "${POSTGRES_PASSWORD+x}" ] && [ -n "${POSTGRES_HOST+x}" ]; then
		#		echo "dbtype = \"pgsql\"" >> "$CONF"
		#		echo "dbhost = \"$POSTGRES_HOST\"" >> "$CONF"
		#		echo "dbname = \"$POSTGRES_DB\"" >> "$CONF"
		#		echo "dbuser = \"$POSTGRES_USER\"" >> "$CONF"
		#		echo "dbpass = \"$POSTGRES_PASSWORD\"" >> "$CONF"
		#	fi

		#	if [ -n "${DB_PREFIX}" ]; then
		#		echo "dbprefix = \"$DB_PREFIX\"" >> "$CONF"
		#	else
		#		echo "dbprefix = \"_flyspray\"" >> "$CONF"
		#	fi

		#	echo >> "$CONF"
		#	echo "[general]" >> "$CONF"
		#	echo "cookiesalt = \"$(openssl rand -hex 16)\"" >> "$CONF"
		#	echo "output_buffering = on" >> "$CONF"
		#	echo "passwdcrypt = \"sha512\"" >> "$CONF"
		#	echo "dot_path = \"/usr/bin/dot\"" >> "$CONF"
		#	echo "dot_format = \"svg\"" >> "$CONF"
		#	echo "reminder_daemon = \"1\"" >> "$CONF"
		#	echo "doku_url = \"http://en.wikipedia.org/wiki\"" >> "$CONF"
		#	
		#	case "${SYNTAX_PLUGIN}" in
		#		html)
		#			echo "syntax_plugin = \"html\"" >> "$CONF"
		#			;;
		#		none)
		#			echo "syntax_plugin = \"none\"" >> "$CONF"
		#			;;
		#		dokuwiki)
		#			echo "syntax_plugin = \"dokuwiki\"" >> "$CONF"
		#			;;
		#		*)
		#			echo "syntax_plugin = \"dokuwiki\"" >> "$CONF"
		#			;;
		#	esac

		#	echo "update_check = \"1\"" >> "$CONF"
		#	echo "\n\n" >> "$CONF"

		#	echo "[attachments]" >> "$CONF"
		#	echo "zip = \"application/zip\"" >> "$CONF"
		#	echo "\n\n" >> "$CONF"

		#	echo "[oauth]" >> "$CONF"

		#	if [ -n "${OA_GITHUB_SECRET}" ] && [ -n "${OA_GITHUB_ID}" ] && [ -n "${OA_GITHUB_REDIRECT}" ]; then
		#		echo "github_secret = \"${OA_GITHUB_SECRECT}\"" >> "$CONF"
		#		echo "github_id = \"${OA_GITHUB_ID}\"" >> "$CONF"
		#		echo "github_redirect = \"${OA_GITHUB_REDIRECT}\"" >> "$CONF"
		#	else
		#		echo "github_secret = \"\"" >> "$CONF"
		#		echo "github_id = \"\"" >> "$CONF"
		#		echo "github_redirect = \"\"" >> "$CONF"
		#	fi

		#	if [ -n "${OA_GOOGLE_SECRET}" ] && [ -n "${OA_GOOGLE_ID}" ] && [ -n "${OA_GOOGLE_REDIRECT}" ]; then
		#		echo "google_secret = \"${OA_GOOGLE_SECRECT}\"" >> "$CONF"
		#		echo "google_id = \"${OA_GOOGLE_ID}\"" >> "$CONF"
		#		echo "google_redirect = \"${OA_GOOGLE_REDIRECT}\"" >> "$CONF"
		#	else
		#		echo "google_secret = \"\"" >> "$CONF"
		#		echo "google_id = \"\"" >> "$CONF"
		#		echo "google_redirect = \"\"" >> "$CONF"
		#	fi

		#	if [ -n "${OA_FACEBOOK_SECRET}" ] && [ -n "${OA_FACEBOOK_ID}" ] && [ -n "${OA_FACEBOOK_REDIRECT}" ]; then
		#		echo "facebook_secret = \"${OA_FACEBOOK_SECRECT}\"" >> "$CONF"
		#		echo "facebook_id = \"${OA_FACEBOOK_ID}\"" >> "$CONF"
		#		echo "facebook_redirect = \"${OA_FACEBOOK_REDIRECT}\"" >> "$CONF"
		#	else
		#		echo "facebook_secret = \"\"" >> "$CONF"
		#		echo "facebook_id = \"\"" >> "$CONF"
		#		echo "facebook_redirect = \"\"" >> "$CONF"
		#	fi

		#	if [ -n "${OA_MICROSOFT_SECRET}" ] && [ -n "${OA_MICROSOFT_ID}" ] && [ -n "${OA_MICROSOFT_REDIRECT}" ]; then
		#		echo "microsoft_secret = \"${OA_MICROSOFT_SECRECT}\"" >> "$CONF"
		#		echo "microsoft_id = \"${OA_MICROSOFT_ID}\"" >> "$CONF"
		#		echo "microsoft_redirect = \"${OA_MICROSOFT_REDIRECT}\"" >> "$CONF"
		#	else
		#		echo "microsoft_secret = \"\"" >> "$CONF"
		#		echo "microsoft_id = \"\"" >> "$CONF"
		#		echo "microsoft_redirect = \"\"" >> "$CONF"
		#	fi

		#rm -rf "/var/www/html/setup"

		fi


	fi
fi
exec "$@"
