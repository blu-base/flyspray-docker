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

		echo "Initializing finished"

		#install
		if [ "$installed_version" = "0.0" ]; then
			echo "New flyspray instance"

			file_env FLYSPRAY_ADMIN_PASSWORD
			file_env FLYSPRAY_ADMIN_USER

			if [ -n "${FLYSPRAY_ADMIN_USER+x}" ] && [ -n "${FLYSPRAY_ADMIN_PASSWORD+x}" ]; then
				# shellcheck disable=SC2016
				install_options='-n --admin-user "$FLYSPRAY_ADMIN_USER" --admin-pass "$FLYSPRAY_ADMIN_PASSWORD"'
				if [ -n "${FLYSPRAY_DATA_DIR+x}" ]; then
					# shellcheck disable=SC2016
					install_options=$install_options' --data-dir "$FLYSPRAY_DATA_DIR"'
				fi

				file_env MYSQL_DATABASE
				file_env MYSQL_PASSWORD
				file_env MYSQL_USER
				file_env POSTGRES_DB
				file_env POSTGRES_PASSWORD
				file_env POSTGRES_USER

				install=false
				if [ -n "${SQLITE_DATABASE+x}" ]; then
					echo "Installing with SQLite database"
					# shellcheck disable=SC2016
					install_options=$install_options' --database-name "$SQLITE_DATABASE"'
					install=true
				elif [ -n "${MYSQL_DATABASE+x}" ] && [ -n "${MYSQL_USER+x}" ] && [ -n "${MYSQL_PASSWORD+x}" ] && [ -n "${MYSQL_HOST+x}" ]; then
					echo "Installing with MySQL database"
					# shellcheck disable=SC2016
					install_options=$install_options' --database mysql --database-name "$MYSQL_DATABASE" --database-user "$MYSQL_USER" --database-pass "$MYSQL_PASSWORD" --database-host "$MYSQL_HOST"'
					install=true
				elif [ -n "${POSTGRES_DB+x}" ] && [ -n "${POSTGRES_USER+x}" ] && [ -n "${POSTGRES_PASSWORD+x}" ] && [ -n "${POSTGRES_HOST+x}" ]; then
					echo "Installing with PostgreSQL database"
					# shellcheck disable=SC2016
					install_options=$install_options' --database pgsql --database-name "$POSTGRES_DB" --database-user "$POSTGRES_USER" --database-pass "$POSTGRES_PASSWORD" --database-host "$POSTGRES_HOST"'
					install=true
				fi
			else
				echo "running web-based installer on first connect!"
			fi

		#upgrade
		# else
		fi
	fi
fi

exec "$@"
