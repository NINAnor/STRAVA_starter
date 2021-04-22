# STRAVA_starter
A set of scripts to do some basic analysis with STRAVA data in Norway

### Introduction
The aim of this repository is to provide reproducible scripts that allow NINA colleagues to do a basic analysis of the STRAVA data and its interaction with environmental data.

### Outputs
* A sorted and cleaned dataframe of STRAVA activities for your study area
* A map of STRAVA activity intensity per trail segment over your study area
* Plots of STRAVA activities aggregated over temporal (monthly) and spatial (ecosystem types) categories
* Plots of STRVA activities against various environmental covariates

### Scope of the scripts and analysis
* NB!! - this is focussed on the "legacy" STRAVA dataset (anything before March 2020) which is stored on NINA R:\ server
  * For data after that point, you need to download from the STRAVA Metro dashboard (https://metroview.strava.com/) and analyse differently
  * The dashbaord solution has different column names, and temporal aggregation procedures, and is therefore difficult to harmonize with legacy data. It also includes sex, age etc.
* Focuses on the monthly STRAVA rollups for 2019 (i.e. excludes annual rollups, hourly data, or origin-destination data)
* Focuses on total activity for pedestrian and cycling categories (i.e. excludes athlete counts, leisure vs commute, activity times, revers vs forward direction)
* Focuses on temporal aggregation (i.e. does not explore time series beyond 1 year long)
* Focuses on relative activity over time and space (i.e. does not calibrate against counter station data to get absolute activity counts)

### Prerequisites
* You need to have access to the RStudio server: http://ninrstudio04.nina.no/
* You need to be a registered Google Earth Engine (GEE) user: https://earthengine.google.com/
* Ideally, to make maps in R, you need to have a Google Maps API key: https://developers.google.com/maps/documentation/javascript/get-api-key

### Workflow
  * Download this entire repository and open up the "STRAVA_R_starter.Rproj" file from RStudio server
  * Create a shapefile outlining your area of interest (AOI) and upload to './DATA/' folder
    *I have placed a Shapefile to start with called "Oslo.shp" which you can use to test-run the scripts
1. Run the "Basic_analysis.R" script line-by-line, changing variable names or path directories to your specific work where necessary.
  * Upload the shapefile that was generated in './DATA/For_GEE/' to your GEE Asset
2. Run the "Environ_data_extract.js" in GEE JavaScript API, changing path directories to your AOI asset. You can copy and paste the script contents into the editor, or follow this code snapshot link: https://code.earthengine.google.com/32ca72b58ddff06c337769df9e5417f8
  * Run the export tasks in the GEE Javascript API. Download them from your Google Drive. Copy them to the './DATA/From_GEE/' folder
3. Run the "Advanced_analysis.R" script in R
