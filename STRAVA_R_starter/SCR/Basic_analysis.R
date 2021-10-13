#Dependencies: having a shapefile in your ./DATA/ folder defining an AOI

# Import libraries (install them first if you do not have already)
library(tidyverse)
library(sf)
library(ggmap)
library(lubridate)
library(ggrepel)
library(ggpubr)
library(BBmisc)
library(RColorBrewer)
library(corrplot)

#### Importing data ------------------------------------------------------------------------
# Define directory strings
mastDir <- '/data/R/GeoSpatialData/LandUse/Norway_StravaData/Original/'
mastDirPed <- paste0(mastDir,'2019/norway_20190101_20191231_ped_edges/Edges/')
mastDirRide <- paste0(mastDir, '2019/norway_south_20190101_20191231_ride_edges/Edges/')

# Import OpenStreetMap shapefile
osm <- st_read(paste0(mastDir, 'Shapefiles/norway_osm_20191217.shp')) %>%
  mutate(edge_id = id) %>%
  dplyr::select(edge_id, km)

# Import polygon defining your area of interest (AOI)
  # here I am using Oslo as an example
aoi <- st_read('./DATA/oslo.shp')

# Make sure the crs of the AOI matches that of OSM
aoi <- st_transform(aoi, crs = st_crs(osm))

# Filter OSM segments for those that intersect with your AOI and then clip them
osm_flitered <- osm %>% 
  filter(st_intersects(geometry, aoi, sparse = FALSE)) %>% 
  st_intersection(aoi)

# Check to see if the OSM shapefile has been clipped to your AOI
ggplot() + 
  geom_sf(data=osm_flitered) + 
  geom_sf(data=aoi, fill=NA, color='red')

# Write out for upload to Google Earth Engine
  # See 'Environ_data_extract.js' script for GEE data export
  # See 'Advanced_analysis.R' script for plotting the output from above
osm_flitered %>%
  st_write('./DATA/For_GEE/osm_flitered.shp')

# Define a vector of your selected OSM "edge_id"
segSelect <- unique(osm_flitered$edge_id)

# Import one CSV to explore column headings
test <- read_csv( paste0(mastDirRide, 'norway_south_20190101_20191231_ride_rollup_month_2019_1_total.csv'),guess_max =100000)
names(test)
# See this doc for variable definitions: https://nina.sharepoint.com/sites/Fag_GIS/Delte%20dokumenter/Strava/Strava-Metro-Comprehensive-User-Guide-Version-8.0.pdf?csf=1&e=biXMf4&cid=93b091c8-2ae8-4606-a103-96cd3871933f
# See this doc for definition of hourly groupings with *_1, *_2 etc. https://nina.sharepoint.com/:w:/r/sites/Fag_GIS/_layouts/15/Doc.aspx?sourcedoc=%7B6FFC2D19-B669-4F19-849F-4DCA5EF2864A%7D&file=Strava%20Data%20in%20NINA.docx&action=default&mobileredirect=true&CID=4E3DBEF0-81D5-43BC-BEA0-FB085641198D&wdLOR=cC23DFC05-173F-4723-9998-634CF95933B7

# I will select the total activity count (tactcnt) for simplicity
  # you could subtract the commute count (cmtcnt) if you want recreational activity
  # you could select the *_1 etc. columns to look at diurnal variations if you want
  # you could also look at activity time (acttime)  to explore speed

# Now iterate over pedestrian (ped) and cycling (ride) CSV files in the GeoSpatialData drive
  # reads in monthly rollups - assuming you want to look at seasonal patterns
  # reads in data for 2019 - need to change for other years
  # you could also read in hourly data, or yearly rollups - depends on your project
months <- seq(1,12,1)

# For ride
ride <- tibble()
for (i in 1:length(months)){
  fileDir <- paste0(mastDirRide, 'norway_south_20190101_20191231_ride_rollup_month_2019_',i,'_total.csv')
  print(fileDir)
  newDat <- read_csv(fileDir,guess_max =100000) %>%
    filter(edge_id %in% segSelect) %>%
    dplyr::select(edge_id, tactcnt)%>%
    mutate(month = i)
  
  ride <- ride %>%
    bind_rows(newDat)
  
}

# for pedestrian
ped <- tibble()
for (i in 1:length(months)){
  fileDir <- paste0(mastDirPed, 'norway_20190101_20191231_ped_rollup_month_2019_',i,'_total.csv')
  print(fileDir)
  newDat <- read_csv(fileDir,guess_max =100000)%>%
    filter(edge_id %in% segSelect) %>%
    dplyr::select(edge_id, tactcnt) %>%
    mutate(month = i)
  
  ped <- ped %>%
    bind_rows(newDat)
  
}


#### Joining and aggregating data ------------------------------------------------------------------------
# Join the ped and ride data frames into one
monthAgg <- ped %>% mutate(type = 'ped') %>%
  bind_rows(ride %>% mutate(type = 'ride')) %>%
  group_by(edge_id, type, month) %>%
  summarise(tactcnt=sum(tactcnt, na.rm=TRUE))


# quickly inspect the data
nrow(monthAgg) # data size
hist(monthAgg$tactcnt) # hist of activity across months and osm segments
hist(monthAgg$month) # spread data availability over months

# You can write it out to the data folder if you want
  # maybe only necessary if the above steps took a long time to run and you don't want to do it
  # each time you run this script
monthAgg %>%
  write_csv('./DATA/STRAVA_month_agg.csv')


#### Mapping the activity ------------------------------------------------------------------------
# First aggregate the data to one value per trail segment per activity
totalAgg <- monthAgg %>%
  # here you can filter to a month range of interest or skip if you want whole year
  filter(month > 4 & month < 8) %>%
  # now summarise over ride and ped activity per segment
  group_by(edge_id, type) %>%
  summarise(tactcnt=sum(tactcnt, na.rm=TRUE))
hist(totalAgg$tactcnt)
hist(log(totalAgg$tactcnt))


# STRAVA do not like us to report actual activity numbers
  # therefore we can normalize activity between 0 and 1
  # we can also normalize log(act + 1) which helps with visualization
totalAgg_norm <- totalAgg %>%
  ungroup() %>%
  mutate(tactcnt_log = normalize(log(tactcnt+1), method='range', range=c(0,1)),
         tactcnt = normalize(tactcnt, method='range', range=c(0,1)))

hist(totalAgg_norm$tactcnt)
hist(totalAgg_norm$tactcnt_log)


## -- At this point you could swith to QGIS for mapping
# merge aggregated data with OSM data and write out a Shapefile for each activity
# first create a folder in ./DATA/ called 'For_GEE'

# pedestrian
osm_flitered  %>%
  left_join(totalAgg_norm%>%
              filter(type == 'ped'), by='edge_id') %>%
  st_write('./DATA/For_QGIS/STRAVA_month_agg_ped.shp')
  
# ride
osm_flitered  %>%
  left_join(totalAgg_norm%>%
              filter(type == 'ride'), by='edge_id') %>%
  st_write('./DATA/For_QGIS/STRAVA_month_agg_ride.shp')


# Now get a base map
  # You can either use Google base maps or you can use Stamen maps - skip to line below with stamen_base
  # for this you need an API key which requires a credit card.
  # don't worry, it is free unless you make thousands of requests to their API
  # follow instructions here: 
  # https://developers.google.com/maps/documentation/javascript/get-api-key

# Enter your Google Maps API key here
your_gmaps_API_key <- "" 
register_google(key = your_gmaps_API_key)

style1 <- c(feature = "all", element = "labels", visibility = "off")
style2 <- c("&style=", feature = "all", element = "geometry", visibility = "off")
style=list(style1, style2)

c <- st_coordinates(st_centroid(aoi))

cent <- c(lon=c[1], lat=c[2])
base <- get_googlemap(center =  cent, 
                      zoom = 11, maptype="hybrid", 
                      scale = 2,
                      style = style,
                      key = your_gmaps_API_key)


# Or if you don't want to get a Google API key, you can use Stamen maps
b <- st_bbox(aoi)
bbox <- c(left = b[[1]], bottom = b[[2]], right = b[[3]], top = b[[4]])

stamen_base <- get_stamenmap(bbox =  bbox,zoom = 11)

# Map the base maps to test
ggmap(base)
ggmap(stamen_base)

# Define parameters for the map
activityType <- 'ped' # can be changed to 'ride'
title <- 'Pedestrian activity summer 2019'

# Now we join with OSM geometries
toPlot <- osm_flitered  %>%
  left_join(totalAgg_norm%>%
              filter(type == activityType), by='edge_id')

# select a palette
display.brewer.all()
# Copy the palette code
palette <-brewer.pal(9, 'YlOrRd')

# Make map
ggmap(stamen_base,# Here you can replace with the google one to compare
      darken=c(0.3, 'black')) +
  geom_sf(data=toPlot, 
          aes(color=tactcnt_log), # here you can play around with raw vs log-trans
          size=0.3, 
          inherit.aes = FALSE)+ 
  scale_color_gradientn(colors=palette,
                        limits = c(0,1), # play around with color scale limits
                        oob = scales::squish) +
  ggtitle(title) +
  theme(legend.position=c(0.15, 0.2),
        legend.background = element_rect(fill=alpha('white',0.5)),
        legend.title=element_blank(),
        legend.key = element_rect(fill = NA)) + 
  # The next bit adds a north arrow and scale bar - need to play around with positioning
  ggsn::north(x.min = 10.7, x.max = 10.73, 
              y.min = 59.85, y.max = 59.87, scale = 2) + 
  ggsn::scalebar(x.min = 10.74, x.max = 10.84, 
                 y.min = 59.85, y.max = 59.87, height = 0.25, model = "WGS84",dist=2,
                 transform=TRUE, dist_unit='km',st.dist = 0.2, st.color='white')

# Click Export in plot console and define dimensions - here you can use 750 x 900

## OR - export to shapefile and do it in QGIS if you want!
toPlot %>%
  st_write('./DATA/for_map_QGIS.shp')
