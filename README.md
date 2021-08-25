Docker container for Flyspray
=============================

[Flyspray](https://www.flyspray.org) is a light-weight open-source bug tracker.
This repository containes the source of a Docker image for that software.

Major parts of the source are shamelessly copied from the [Nextcloud](https://github.com/nextcloud/docker)
Docker container source and adapted to the needs of Flyspray.

Consider this **project under development**, since the adaption is not completed
yet.

# How to use this image

This image is designed to be used in a micro-service environment. There
currently is only one image version which is based on Debian and apache.

## using the apache image
The apache image contains a webserver and exposes port 80. To start the container
type:

```
$ docker run -d -p 8080:80 flyspray
```
Now you can access Flyspray at http://localhost:8080/ from your host system.

## Using an external database
By default, this container uses PostgreSQL for data storage but the Flyspray 
setup wizard (appears on first run) allows connecting to an existing MySQL or 
PostgreSQL database. You can also link a database container, e. g. 
`--link my-mysql:mysql`, and then use `mysql` as the database host on setup. 
More info is in the docker-compose section.

## Persistent data
The flyspray installation and all data beyond what lives in the database (file 
uploads, etc.) are stored in the [unnamed docker volume](https://docs.docker.com/engine/tutorials/dockervolumes/#adding-a-data-volume) 
volume `/var/www/html`. The docker daemon will store that data within the docker
directory `/var/lib/docker/volumes/...`. That means your data is saved even if 
the container crashes, is stopped or deleted.

A named Docker volume or a mounted host directory should be used for upgrades 
and backups. To achieve this, you need one volume for your database container 
and one for Flyspray.

Flyspray:
- `/var/www/html/` folder where all Flyspray data lives
```console
$ docker run -d \
-v flyspray:/var/www/html \
flyspray
```

Database:
- `/var/lib/mysql` MySQL / MariaDB Data
- `/var/lib/postgresql/data` PostgreSQL Data
```console
$ docker run -d \
-v db:/var/lib/mysql \
mariadb:10.5
```

If you want to get fine grained access to your individual files, you can mount 
additional volumes for data, config, your theme and plugins. These
directories are stored inside `/var/www/html/`.  If you use a custom theme it 
would go into the `themes` subfolder.

Overview of the folders that can be mounted as volumes:

- `/var/www/html` Main folder, needed for updating
- `/var/www/html/themes/<YOUR_CUSTOM_THEME>` theming/branding

If you want to use named volumes for all of these, it would look like this:
```console
$ docker run -d \
-v flyspray:/var/www/html \
flyspray
```

## Auto configuration via environment variables
The Flyspray image supports auto configuration via environment variables. You
can preconfigure everything that is asked on the install page on first run. To
enable auto configuration, set your database connection via the following
environment variables. You must specify all of the environment variables for a
given database.
ONLY use one database type!

__MYSQL/MariaDB__:
- `MYSQL_DATABASE` Name of the database using mysql / mariadb.
- `MYSQL_USER` Username for the database using mysql / mariadb.
- `MYSQL_PASSWORD` Password for the database user using mysql / mariadb.
- `MYSQL_HOST` Hostname of the database server using mysql / mariadb.

__PostgreSQL__:
- `POSTGRES_DB` Name of the database using postgres.
- `POSTGRES_USER` Username for the database using postgres.
- `POSTGRES_PASSWORD` Password for the database user using postgres.
- `POSTGRES_HOST` Hostname of the database server using postgres.

If you set any values, they will not be asked in the install page on first run.
With a complete configuration by using all variables for your database type, you
can additionally configure your Flyspray instance by setting admin user and 
password (only works if you set both):

- `FS_ADMIN_USERNAME` Name of the Flyspray admin user.
- `FS_ADMIN_PASSWORD_FILE` Password file for the Flyspray admin user.
- `FS_ADMIN_EMAIL` Email of the Flyspray admin user.
- `FS_ADMIN_XMPP` XMPP address of the Flyspray admin user (optional).
- `FS_ADMIN_REALNAME` Displayed name of the admin user (optional).

- `DB_PREFIX` The Table prefix used for Flyspray (optional, defaults to `flyspray_`).
- `FS_SYNTAX_PLUGIN` Selects which editor is used for Flyspray submissions (optional, defaults to `dokuwiki`).
- `FS_REMINDER_DAEMON` Selects which method is used to timed notifications (optional, defaults to `0`(cron)).

If you want to use any of the supported OAuth provide, you must specify the set
of ID, secret and redirection address.

- `FS_OA_GITHUB_ID`
- `FS_OA_GITHUB_REDIRECT`
- `FS_OA_GITHUB_SECRET_FILE`

- `FS_OA_GOOGLE_ID`
- `FS_OA_GOOGLE_REDIRECT`
- `FS_OA_GOOGLE_SECRET_FILE`

- `FS_OA_MICROSOFT_ID`
- `FS_OA_MICROSOFT_REDIRECT`
- `FS_OA_MICROSOFT_SECRET_FILE`


# Running this image with docker-compose
The easiest way to get a fully featured and functional setup is using a `docker-compose` file. There are too many different possibilities to setup your system.
For this reason, only a few examples are given below.

At first, make sure you have chosen the right features you wanted (see below). In every case, you would want to add a database container and docker volumes to get easy access to your persistent data.

## Just get started
In the root `stack.yml` shows a sample for a docker-compose setup. It uses a PostgresSQL database, Apache web-server, docker secrets for credentials, and a separate container for cron tasks. To get this started follow these steps:

Copy this file into the desired release, such as master/apache, then change into this directory:
```bash
cp stack.yml master/apache/docker-compose.yml
cd master/apache
```

Check the environment values set in `docker-compose.yml`. Make sure the database credentials are identical for the db container and flyspray container.

Set the password files. Make sure you have no trailing newline symbols (`-n` option for echo). 
```bash
echo -n "mydbpassword" > db_password.txt
echo -n "myfsadminpassword" > fs_admin_password.txt
```
Set the file permission and ownership of these files. For example, run:
```bash
sudo bash -c 'for f in db_password.txt fs_admin_password.txt; do chown 0:0 $f; chmod 660 $f; done'
```

Now, you need to build the image:
```bash
docker build -t flyspray .
```

Finally, run docker-compose to startup the services:
```bash
docker-compose up -d
```
The initialization will take a few momemnts after the apache container is ready.
Then you'll be able to access Flyspray via `http://localhost:8080`.
Login with the admin credentials given by `FS_ADMIN_USERNAME` and `FS_ADMIN_PASSWORD_FILE`, by default `admin` and `myfsadminpassword`, respectively.

# Docker Secrets
As an alternative to passing sensitive information via environment variables, `_FILE` may be appended to the previously listed environment variables, causing the initialization script to load the values for those variables from files present in the container. For the passwords for postgres, mysql, and the flyspray admin this is the only permitted approach for this container. An example:
```yaml
version: '3.2'

services:
  db:
    image: postgres
    restart: always
    volumes:
      - db:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB_FILE=/run/secrets/postgres_db
      - POSTGRES_USER_FILE=/run/secrets/postgres_user
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
    secrets:
      - postgres_db
      - postgres_password
      - postgres_user

  app:
    image: flyspray
    restart: always
    ports:
      - 8080:80
    volumes:
      - flyspray:/var/www/html
    environment:
      - POSTGRES_HOST=db:5432
      - POSTGRES_DB_FILE=/run/secrets/postgres_db
      - POSTGRES_USER_FILE=/run/secrets/postgres_user
      - POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password
      - FS_ADMIN_PASSWORD_FILE=/run/secrets/fs_admin_password
      - FS_ADMIN_USERNAME_FILE=/run/secrets/fs_admin_user
    depends_on:
      - db
    secrets:
      - fs_admin_password
      - fs_admin_user
      - postgres_db
      - postgres_password
      - postgres_user

volumes:
  db:
  flyspray:

secrets:
  fs_admin_password:
    file: ./fs_admin_password.txt # put admin password to this file
  fs_admin_user:
    file: ./fs_admin_user.txt # put admin username to this file
  postgres_db:
    file: ./postgres_db.txt # put postgresql db name to this file
  postgres_password:
    file: ./postgres_password.txt # put postgresql password to this file
  postgres_user:
    file: ./postgres_user.txt # put postgresql username to this file
```

# Questions / Issues
If you got any questions or problems using the image, please visit the [Github Repository](https://github.com/blu-base/flyspray-docker) and write an issue.
