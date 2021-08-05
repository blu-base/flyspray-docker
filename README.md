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
Now you can access Nextcloud at http://localhost:8080/ from your host system.

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
-v theme:/var/www/html/themes/<YOUR_CUSTOM_THEME> \
nextcloud
```


## Auto configuration via environment variables
The Flyspray image supports auto configuration via environment variables. You
can preconfigure everything that is asked on the install page on first run. To
enable auto configuration, set your database connection via the following
environment variables. You must specify all of the environment variables for a
given database or the database environment variables defaults to SQLITE.
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

- `FLYSPRAY_ADMIN_USER` Name of the Flyspray admin user.
- `FLYSPRAY_ADMIN_PASSWORD` Password for the Flyspray admin user.

** Setting the admin account this way does currently not work!... **



