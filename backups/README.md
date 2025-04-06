# Dashboard Backup

InfluxDB is configured to use a infinite retention policy (see [influxdb.sql](../influxdb/influxdb.sql)).  It uses continuous queries to downsample Powerwall data and preserve disk space.  However, this does not safeguard the data from accidental deletion or corruption.  It is recommend that you set up a backup plan to snapshot the data for disaster recovery.

## Transfer to a New Computer

If you want to create a backup of your Powerwall Dashboard and move it to a new computer. You can follow these steps:

```bash
# Step 1 - Stop Dashboard on old computer
./compose-dash.sh stop

# Step 2- Create a backup
sudo tar -zvcf ../Powerwall-Dashboard.tgz *
cd ..

# Step 3 - Copy the Powerwall-Dashboard.tgz to the new computer

# Stop 4 - Clone Project on new computer
git clone https://github.com/jasonacox/Powerwall-Dashboard.git
cd Powerwall-Dashboard

# Step 5 - Restore backup
sudo tar --no-same-owner -zxvf ../Powerwall-Dashboard.tgz

# Step 6 - Setup
./setup.sh
```

## Backup Plans

Backup the Powerwall-Dashboard folder. In that folder are two important folders:

* influxdb - This is the folder for the database that stores the metrics.
* grafana - This is the folder for the dashboard which holds your setup and customization.

The following shows an example of how to migrate the data (influxdb) from one system to another (see backup.sh):

1. Copy backup.sh.sample to backup.sh (cp backup.sh.sample backup.sh)
2. Edit the line that says DASHBOARD="/home/user/Powerwall-Dashboard" to have your dashboard location.
3. Make the script executable with `chmod +x backup.sh`

## Backup Script Example

```bash
#!/bin/bash
# Daily Backup for Powerwall-Dashboard Data
if [ "$EUID" -ne 0 ]
  then echo "Must run as root"
  exit
fi

# Set values for your environment 
DASHBOARD="/home/user/Powerwall-Dashboard"    # Location of Dashboard to backup
BACKUP_FOLDER="${DASHBOARD}/backups"          # Destination folder for backups
KEEP="5"                                      # Days to keep backup

# Check to see if directory exists
if [ ! -d "${DASHBOARD}" ]; then
  echo "Dashboard directory ${DASHBOARD} does not exist."
  exit
fi
if [ ! -d "${BACKUP_FOLDER}" ]; then
  echo "Backup directory ${BACKUP_FOLDER} does not exist."
  exit
fi

# Timestamp for Backup Filename
STAMP=$(date '+%Y-%m-%d')

# Optional: Ask InfluxDB to create a snapshot backup 
echo "Creating InfluxDB Backup"
cd ${DASHBOARD}
mkdir -p influxdb/backups
chmod g+w influxdb/backups
docker exec influxdb influxd backup -database powerwall /var/lib/influxdb/backups

# Backup Powerwall-Dashboard Data
echo "Backing up Powerwall-Dashboard Data (influxdb)"
cd  ${DASHBOARD}
tar -Jcvf ${BACKUP_FOLDER}/Powerwall-Dashboard.$STAMP.tar.xz influxdb 

# Cleanup Old Backups
echo "Cleaning up old backups"
rm -rf ${DASHBOARD}/influxdb/backups/*        # Delete InfluxDB snapshots after backup
find ${BACKUP_FOLDER}/Powerwall-Dashboard.*tar.xz -mtime +${KEEP} -type f -delete
echo "Done"
```

## Restore Backup

Naturally, whatever backup plan you decide to do, make sure you test it. Copy the backup to another VM or box, install Powerwall-Dashboard and restore the backup to see if it all comes back up without any data loss.

1. Install a fresh instance of Powerwall-Dashboard per [Setup instructions](https://github.com/jasonacox/Powerwall-Dashboard#setup).
2. Stop containers using convenience script in Powerwall-Dashboard root folder
    ```bash
    ./compose-dash.sh stop
    ```
3. Restore backup files
    ```bash
    # Inside the Powerwall-Dashboard folder, extract the backup archive
    sudo tar --no-same-owner -Jxvf /backups/Powerwall-Dashboard.xyz.tar.xz
    ```
4. Start containers
    ```bash
    ./compose-dash.sh start
    ```
