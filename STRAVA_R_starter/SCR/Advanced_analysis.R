# Dependencies: 
  # You should have run the 'Basic_analysis.R' script
    # upload to GEE
  # You should have run the 'Environ_data_extract.js' script
    # download GEE output CSV files to './DATA/From_GEE/'

# Set ggplot theme
theme_set(theme_bw()+ 
            theme(panel.grid.major = element_blank(), panel.grid.minor = element_blank())+
            theme(strip.background =element_rect(fill="white")))

#### Importing data ------------------------------------------------------------------------
# Import strava activity summarised data
  # you can either use object created in 'Basic_analysis.R' script
strava <- monthAgg
  # Or you can import the data you wrote out
strava <- read_csv('./DATA/STRAVA_month_agg.csv')

# Import the OSM geometry lengths
osmLengths <- st_read('./DATA/For_GEE/osm_flitered.shp') %>%
  as_tibble() %>%
  dplyr::select(edge_id, km)
 
# Import continuous variables from GEE
envVar_cont <- read_csv('./DATA/From_GEE/explan_vars_continuous.csv') %>%
  dplyr::select(-`system:index`, -".geo", -km )
names(envVar_cont)

# Import categorical variables from GEE
envVar_cat <- read_csv('./DATA/From_GEE/explan_vars_categorical.csv') %>%
  mutate(ecoTypes = factor(mode)) %>%
  dplyr::select(edge_id, ecoTypes) %>%
  drop_na(ecoTypes)

# Reclassify categorical variable from numeric levels defined in GEE
  # need to only include levels that are present in the dataset
levels(envVar_cat$ecoTypes)

# reclassify
levels(envVar_cat$ecoTypes) <- c('Skog',
                                # 'Fjell', # 2 not present
                                # 'Arktisk tunrda',  # 3 not present
                                 'Vatmark', 
                                 'Semi-naturlig', 
                                 'Naturlig Apent',
                                 'Hav', 
                                 'Ferskvann', 
                                 'Jordbruk', 
                                 'Bebygd')

# Summarize trail lengths per area class
  # this will be used to calculate activity intensity relative to trail availability
areaCatTrailLength <- osmLengths%>%
  left_join(envVar_cat, by='edge_id')%>%
  drop_na(ecoTypes) %>%
  group_by(ecoTypes) %>%
  summarise(length = sum(km, na.rm=TRUE))

#### Plots with categorical variables -----------------------------------------------------------
# Join the strava and categorical data
# Summarise to sum of activities per activity type, per area category and per month
catStrava_monthly <- strava %>%
  left_join(osmLengths, by='edge_id') %>%
  # here we weight the number of activities by the length of the trail segment
  mutate(tactcnt = tactcnt*km) %>%
  drop_na(tactcnt) %>%
  left_join(envVar_cat, by='edge_id') %>%
  drop_na(ecoTypes)  %>%
  left_join(areaCatTrailLength, by='ecoTypes') %>%
  mutate(tact_relKm = tactcnt/length) %>%
  group_by(month, type) %>%
  mutate(actPerMonth = sum(tactcnt, na.rm=TRUE),
         actPerMonth_relKm = sum(tact_relKm, na.rm=TRUE))%>%
  group_by(month, type, ecoTypes, actPerMonth,actPerMonth_relKm) %>%
  summarise(tactcnt = sum(tactcnt, na.rm=TRUE),
            tact_relKm = sum(tact_relKm, na.rm=TRUE)) %>%
  mutate(tactPerc = tactcnt/actPerMonth*100,
         tactPerc_relKm  = tact_relKm /actPerMonth_relKm *100)

# Color palette for the levels of the area category
cat_palette <- c('#00911d', #skog 1
                 #'#bcbcbc', #fjell 2
                 #'#b4ff8e', #tundra 3
                 '#38ffe7', # vatmark 4
                 '#f2e341', # semi-natural 5
                 '#eb56ff', # apent 6
                 '#2163ff', # hav 7
                 '#19b8f7', # freshwater 8
                 '#f28f84', # croplan 9
                 '#ff0000') # urban 10

# Plot activity totals for area types per month
catStrava_monthly %>%
  ggplot(aes(x=factor(month), y=tactcnt, fill=ecoTypes)) +
  geom_bar(stat='identity', position='stack') +
  facet_wrap(~type) +
  scale_fill_manual(values=cat_palette)

# Plot activity totals for area types per month - but relative to trail length available
catStrava_monthly %>%
  ggplot(aes(x=factor(month), y=tact_relKm, fill=ecoTypes)) +
  geom_bar(stat='identity', position='stack') +
  facet_wrap(~type) +
  scale_fill_manual(values=cat_palette)

# Plot like above but proportions
catStrava_monthly %>%
  ggplot(aes(x=factor(month), y=tactPerc, fill=ecoTypes)) +
  geom_bar(stat='identity', position='stack') +
  facet_wrap(~type) +
  scale_fill_manual(values=cat_palette)

# Plot like above but proportions - but relative to trail length available
catStrava_monthly %>%
  ggplot(aes(x=factor(month), y=tactPerc_relKm, fill=ecoTypes)) +
  geom_bar(stat='identity', position='stack') +
  facet_wrap(~type) +
  scale_fill_manual(values=cat_palette)

# Plot total activities by month and faceted by area category
catStrava_monthly %>%
  ggplot(aes(x=month, y=tactcnt, color=type)) +
  geom_point() +
  geom_line() +
  facet_wrap(~ecoTypes, 
             scales='free_y') # makes the y-axis different for each plot

# Plot like above but switch activity type for area type
catStrava_monthly %>%
  ggplot(aes(x=month, y=tactcnt, color=ecoTypes)) +
  geom_point() +
  geom_line() +
  scale_fill_manual(values=cat_palette)+
  facet_wrap(~type, 
             scales='free_y') # makes the y-axis different for each plot


#### Plots with continuous variables -----------------------------------------------------------
# I am going to aggregate strava data to annual sum per trail segment
  # you could do summer/winter/per month etc. if you want
stravaAggYear <- strava %>%
  group_by(edge_id, type) %>%
  summarise(tactcnt = sum(tactcnt, na.rm=TRUE)) %>%
  # Again we weight the number of activities by the length of the trail segment
  left_join(osmLengths, by='edge_id') %>%
  mutate(tactcnt = tactcnt*km) %>%
  drop_na(tactcnt)

# Join with continuous variables
contStrava <- stravaAggYear %>%
  left_join(envVar_cont, by='edge_id') %>%
  drop_na(ndvi) %>%
  # here we can normalize and log-transform again
  ungroup() %>%
  mutate(tactcnt_log = normalize(log(tactcnt+1), method='range', range=c(0,1)),
         tactcnt = normalize(tactcnt, method='range', range=c(0,1)))

# See data distributions - histograms for each variable
contStrava %>%
  gather(key, val, tactcnt:tactcnt_log) %>%
  ggplot(aes(x=val)) +
  geom_histogram() +
  facet_wrap(~key, scales='free')

# Make a correlation matrix (this assumes linear relationships between variables)
# choose activity type
activityType <- 'ped'
matrix <- contStrava %>% ungroup() %>%
  filter(type == activityType) %>%
  dplyr::select(tactcnt_log, elevation, ndvi,trailDens) %>%
  drop_na()
colSums(is.na(matrix))
M <- cor(as.data.frame(matrix))
corrplot(M, type = "upper", tl.cex=0.8, tl.col='#000000', col = brewer.pal(n = 8, name = "PuOr"))

# Plot two-way relationships
contStrava %>%
  ggplot(aes(x=trailDens, y=tactcnt_log)) +
  geom_point(shape='.') +
  geom_smooth() +
  facet_wrap(~type, scales='free')

# Plot multi-way relationships
  # first have to normalize explanatory variables
contStrava %>%
  gather(key, val, ndvi, elevation, trailDens) %>%
  group_by(type, key) %>%
  mutate(val = normalize(val, method='range', range=c(0,1))) %>%
  ggplot(aes(x=val, y=tactcnt_log, color=key)) +
  geom_smooth()  +
  facet_wrap(~type, scales='free')

