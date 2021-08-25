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

## HACK function to initialize after db and apache have been started
setup() {
	if [ "$installed_version" = "0.0" ]; then
		echo "New flyspray instance"
		file_env MYSQL_HOST
		file_env MYSQL_DATABASE
		file_env MYSQL_USER
		file_env POSTGRES_HOST 'db:5432'
		file_env POSTGRES_DB
		file_env POSTGRES_USER

		file_env DB_PREFIX 'flyspray_'
		file_env FS_SYNTAX_PLUGIN 'dokuwiki'
		file_env FS_REMINDER_DAEMON '1'

		file_env FS_ADMIN_USERNAME 'admin'
		file_env FS_ADMIN_EMAIL 'admin@example.com'
		file_env FS_ADMIN_XMPP ''
		file_env FS_ADMIN_REALNAME ''

		file_env FS_OA_GITHUB_ID ''
		file_env FS_OA_GITHUB_REDIRECT ''
		file_env FS_OA_GOOGLE_ID ''
		file_env FS_OA_GOOGLE_REDIRECT ''
		file_env FS_OA_MICROSOFT_ID ''
		file_env FS_OA_MICROSOFT_REDIRECT ''



		if [ -n "${MYSQL_DATABASE}" ] && [ -n "${MYSQL_USER}" ] && [ -n "${MYSQL_PASSWORD_FILE}" ] && [ -n "${MYSQL_HOST}" ]; then
			DB_TYPE='mysqli'
			DB_HOST="${MYSQL_HOST}"
			DB_NAME="${MYSQL_DATABASE}"
			DB_PW_FILE="${MYSQL_PASSWORD_FILE}"
			DB_USER="${MYSQL_USER}"
		elif [ -n "${POSTGRES_DB}" ] && [ -n "${POSTGRES_USER}" ] && [ -n "${POSTGRES_PASSWORD_FILE}" ] && [ -n "${POSTGRES_HOST}" ]; then
			DB_TYPE='pgsql'
			DB_HOST="${POSTGRES_HOST}"
			DB_NAME="${POSTGRES_DB}"
			DB_PW_FILE="${POSTGRES_PASSWORD_FILE}"
			DB_USER="${POSTGRES_USER}"
		else
			echo >&2 "The provided database login is not valid.\nEither provide (MYSQL_DATABASE, MYSQL_USER, MYSQL_PASSWORD_FILE, MYSQL_HOST),\nor (POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD_FILE, POSTGRES_HOST)."
			exit 1
		fi

		## say hello
		PHPSESSID=$(curl -s -I http://localhost/setup/index.php \
			-X GET \
			-H 'Accept: text/html' \
			-H 'Accept-Language: en-US,en;q=0.5' \
			-H 'Connection: keep-alive' \
			-H 'Upgrade-Insecure-Requests: 1' \
			-H 'Sec-Fetch-Dest: document' \
			-H 'Sec-Fetch-Mode: navigate' \
			-H 'Sec-Fetch-Side: none' \
			-H 'Sec-Fetch-User: ?1' \
			-H 'Host: localhost' \
			| grep Set-Cookie \
			| sed 's/.*PHPSESSID=\([a-f0-9]*\); .*/\1/g' \
		)

		## visit pre-installation check
		curl -s http://localhost/setup/index.php \
			-X POST \
			-H 'Accept: text/html' \
			-H 'Accept-Language: en-US,en;q=0.5' \
			-H 'Content-Type: application/x-www-form-urlencoded' \
			-H 'Connection: keep-alive' \
			-H "Cookie: PHPSESSID=$PHPSESSID" \
			-H 'Upgrade-Insecure-Requests: 1' \
			-H 'Sec-Fetch-Dest: document' \
			-H 'Sec-Fetch-Mode: navigate' \
			-H 'Sec-Fetch-Side: same-origin' \
			-H 'Sec-Fetch-User: ?1' \
			-H 'Host: localhost' \
			--data-urlencode "action=database" \
			--data-urlencode "next=next"

		## populate the db
		curl -s http://localhost/setup/index.php \
			-X POST \
			-H 'Accept: text/html' \
			-H 'Accept-Language: en-US,en;q=0.5' \
			-H 'Content-Type: application/x-www-form-urlencoded' \
			-H 'Connection: keep-alive' \
			-H "Cookie: PHPSESSID=$PHPSESSID" \
			-H 'Upgrade-Insecure-Requests: 1' \
			-H 'Sec-Fetch-Dest: document' \
			-H 'Sec-Fetch-Mode: navigate' \
			-H 'Sec-Fetch-Side: same-origin' \
			-H 'Sec-Fetch-User: ?1' \
			-H 'Host: localhost' \
			--data-urlencode "db_type=$DB_TYPE" \
			--data-urlencode "db_hostname=$DB_HOST" \
			--data-urlencode "db_name=$DB_NAME" \
			--data-urlencode "db_username=$DB_USER" \
			--data-urlencode "db_password@$DB_PW_FILE" \
			--data-urlencode "db_prefix=$DB_PREFIX" \
			--data-urlencode "action=administration" \
			--data-urlencode "next=next"

		## final flyspray setup
		curl -s http://localhost/setup/index.php \
			-X POST \
			-H 'Accept: text/html' \
			-H 'Accept-Language: en-US,en;q=0.5' \
			-H 'Content-Type: application/x-www-form-urlencoded' \
			-H 'Connection: keep-alive' \
			-H "Cookie: PHPSESSID=$PHPSESSID" \
			-H 'Upgrade-Insecure-Requests: 1' \
			-H 'Sec-Fetch-Dest: document' \
			-H 'Sec-Fetch-Mode: navigate' \
			-H 'Sec-Fetch-Side: same-origin' \
			-H 'Sec-Fetch-User: ?1' \
			-H 'Host: localhost' \
			--data-urlencode "db_type=$DB_TYPE" \
			--data-urlencode "db_hostname=$DB_HOST" \
			--data-urlencode "db_name=$DB_NAME" \
			--data-urlencode "db_username=$DB_USER" \
			--data-urlencode "db_password@$DB_PW_FILE" \
			--data-urlencode "db_prefix=$DB_PREFIX" \
			--data-urlencode "admin_username=$FS_ADMIN_USERNAME" \
			--data-urlencode "admin_password@$FS_ADMIN_PASSWORD_FILE" \
			--data-urlencode "admin_email=$FS_ADMIN_EMAIL" \
			--data-urlencode "admin_realname=$FS_ADMIN_REALNAME" \
			--data-urlencode "admin_xmpp=$FS_ADMIN_XMPP" \
			--data-urlencode "syntax_plugin=$FS_SYNTAX_PLUGIN" \
			--data-urlencode "reminder_daemon=$FS_REMINDER_DAEMON" \
			--data-urlencode "action=complete" \
			--data-urlencode "next=Next+>>"

		## after-setup cleanup
		echo "Run Flyspray after-setup clean-up"
		curl -s http://localhost/setup/cleanupaftersetup.php


		# use soa password encryption
		echo "Set password encrpytion"
		sed -i "s/^\(passwdcrypt =\) .*/\1 \"sha512\"/g" /var/www/html/flyspray.conf.php

		# add support for graphs
		echo "Setup for dot graphs"
		sed -i "s|^\(dot_path =\) .*|\1 \"/usr/bin/dot\"|g" /var/www/html/flyspray.conf.php
		sed -i "s/^\(dot_format =\) .*/\1 \"svg\"/g" /var/www/html/flyspray.conf.php


		# add oauth provider
		echo "Checking OAuth provider setup:"
		echo -n "Github..."
		if [ -n "${FS_OA_GITHUB_SECRET_FILE}" ] && [ -n "${FS_OA_GITHUB_ID}" ] && [ -n "${FS_OA_GITHUB_REDIRECT}" ]; then
			echo "setting up."
			sed -i "s/^\(github_secret\) =.*/\1 = '$(cat $FS_OA_GITHUB_SECRET_FILE)'/g" /var/www/html/flyspray.conf.php
			sed -i "s/^\(github_id\) =.*/\1 = '$FS_OA_GITHUB_ID'/g" /var/www/html/flyspray.conf.php
			sed -i "s/^\(github_redirect\) =.*/\1 = '$FS_OA_GITHUB_REDIRECT'/g" /var/www/html/flyspray.conf.php
		else
			echo "skipping."
		fi

		echo -n "Google..."
		if [ -n "${FS_OA_GOOGLE_SECRET_FILE}" ] && [ -n "${FS_OA_GOOGLE_ID}" ] && [ -n "${FS_OA_GOOGLE_REDIRECT}" ]; then
			echo "setting up."
			sed -i "s/^\(google_secret\) =.*/\1 = '$(cat $FS_OA_GOOGLE_SECRET_FILE)'/g" /var/www/html/flyspray.conf.php
			sed -i "s/^\(google_id\) =.*/\1 = '$FS_OA_GOOGLE_ID'/g" /var/www/html/flyspray.conf.php
			sed -i "s/^\(google_redirect\) =.*/\1 = '$FS_OA_GOOGLE_REDIRECT'/g" /var/www/html/flyspray.conf.php
		else
			echo "skipping."
		fi

		echo -n "Microsoft..."
		if [ -n "${FS_OA_MICROSOFT_SECRET_FILE}" ] && [ -n "${FS_OA_MICROSOFT_ID}" ] && [ -n "${FS_OA_MICROSOFT_REDIRECT}" ]; then
			echo "setting up."
			sed -i "s/^\(microsoft_secret\) =.*/\1 = '$(cat $FS_OA_MICROSOFT_SECRET_FILE)'/g" /var/www/html/flyspray.conf.php
			sed -i "s/^\(microsoft_id\) =.*/\1 = '$FS_OA_MICROSOFT_ID'/g" /var/www/html/flyspray.conf.php
			sed -i "s/^\(microsoft_redirect\) =.*/\1 = '$FS_OA_MICROSOFT_REDIRECT'/g" /var/www/html/flyspray.conf.php
		else
			echo "skipping."
		fi
	else
		#existing instance
		return
	fi
}



if expr "$1" : "apache" 1>/dev/null; then
	if [ -n "${APACHE_DISABLE_REWRITE_IP+x}" ]; then
		a2disconf remoteip
	fi
fi

if expr "$1" : "apache" 1>/dev/null || [ "$1" = "php-fpm" ] || [ "${FLYSPRAY_UPDATE:-0}" -eq 1 ]; then

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
		echo "Setting .htaccess"
		if expr "$1" : "apache" 1>/dev/null; then
			if [ -f "/var/www/html/htaccess.dist" ]; then
				mv "/var/www/html/htaccess.dist" "/var/www/html/.htaccess"
			fi
		fi

		echo "Static initialization finished"

	fi
fi

(echo "Scheduling Instance setup..."; sleep 5; echo "Setting up the instance."; setup;) & exec "$@"
