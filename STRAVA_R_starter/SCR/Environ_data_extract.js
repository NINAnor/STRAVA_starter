 // Author: Zander Venter - zander.venter@nina.no

// This code is part of a workflow to map STRAVA data for NINA projects
// All the data in this script is available over whole Norway

// Workflow in this script:
  // 1. Import filtered OSM geometries for area of interest (uploaded from R)
  // 2. Collect environmental datasets
  // 3. Extract values for OSM geometries and export as CSV


/*
  // Global functions ///////////////////////////////////////////////////////////////////////////////
*/
// Get distance to pixels with 1
function getDistance(image){
  return image.fastDistanceTransform(1040).sqrt()
  .multiply(ee.Image.pixelArea().sqrt()).divide(1000);
}

// Function to mask clouds using the Sentinel-2 QA band.
function maskS2clouds(img) {
  var qa = img.select('QA60').int16();
  var cloudBitMask = Math.pow(2, 10);
  var cirrusBitMask = Math.pow(2, 11);
  var mask = qa.bitwiseAnd(cloudBitMask).eq(0).and(
             qa.bitwiseAnd(cirrusBitMask).eq(0));
  return img.updateMask(mask);
}

// Function to add spectral indices to Sentinel images
var addIndices = function(image) {
  var ndbi = image.expression(
    '(SWIR - NIR) / (SWIR + NIR)', {
      'SWIR': image.select('swir1'),
      'NIR': image.select('nir'),
    }).rename('NDBI');
  // Add vegetation indices
  var ndvi = image.normalizedDifference(['nir', 'red']).rename('ndvi')
  return image.addBands(ndvi)//.addBands(ndbi)
};

//This procedure must be used for proper processing of S2 imagery
function uniqueValues(collection,field){
    var values  =ee.Dictionary(collection.reduceColumns(ee.Reducer.frequencyHistogram(),[field]).get('histogram')).keys();
    return values;
  }
function dailyMosaics(imgs){
  //Simplify date to exclude time of day
  imgs = imgs.map(function(img){
  var d = ee.Date(img.get('system:time_start'));
  var day = d.get('day');
  var m = d.get('month');
  var y = d.get('year');
  var simpleDate = ee.Date.fromYMD(y,m,day);
  return img.set('simpleTime',simpleDate.millis());
  });
  
  //Find the unique days
  var days = uniqueValues(imgs,'simpleTime');
  
  imgs = days.map(function(d){
    d = ee.Number.parse(d);
    d = ee.Date(d);
    var t = imgs.filterDate(d,d.advance(1,'day'));
    var f = ee.Image(t.first());
    t = t.mosaic();
    t = t.set('system:time_start',d.millis());
    t = t.copyProperties(f);
    return t;
    });
    imgs = ee.ImageCollection.fromImages(imgs);
    
    return imgs;
}


/*
  // Import data ///////////////////////////////////////////////////////////////////////////////
*/

// Import OSM segments
  // Replace asset ID with your own
var osm = ee.FeatureCollection('users/zandersamuel/NINA/Vector/Oslo_osm_flitered');

Map.addLayer(osm, {}, 'osm segments')
Map.centerObject(osm.first(), 10)

// Define AOI manually by
  // drawing a geometry around your trail segments using the geometry tools in left of map
  // first delete the one that is already there
var aoi = geometry;

// Clip OSM geometries to aoi
osm = osm.map(function(ft){
  return ft.intersection(aoi, 10)
})

Map.addLayer(osm, {}, 'osm segments clipped')

// ------- Høvedøkosystemkart - main ecosystem types ----------------------------------
  // reclassification of AR5 and AR50 maps
var ecoTypes = ee.Image('users/zandersamuel/NINA/Raster/Norway_ecosystem_types_5m');

// Reclassify image to a simple typology
ecoTypes = ecoTypes
  .where(ecoTypes.gt(100).and(ecoTypes.lt(200)),1)
  .where(ecoTypes.gt(200).and(ecoTypes.lt(300)),2)
  .where(ecoTypes.gt(300).and(ecoTypes.lt(400)),3)
  .where(ecoTypes.gt(400).and(ecoTypes.lt(500)),4)
  .where(ecoTypes.gt(500).and(ecoTypes.lt(600)),5)
  .where(ecoTypes.gt(600).and(ecoTypes.lt(700)),6)
  .where(ecoTypes.gt(700).and(ecoTypes.lt(800)),7)
  .where(ecoTypes.eq(802).or(ecoTypes.eq(801)),8)
  .where(ecoTypes.gt(802).and(ecoTypes.lt(840)),9)
  .where(ecoTypes.gt(840),10);
ecoTypes = ecoTypes.rename('ecoTypes');

var vizParams = {
  min: 1,
  max: 10,
  palette: [
    '#00911d', //skog 1
    '#bcbcbc', //fjell 2
    '#b4ff8e', //tundra 3
    '#38ffe7', // vatmark 4
    '#f2e341', // semi-natural 5
    '#eb56ff', // apent 6
    '#2163ff', // hav 7
    '#19b8f7',// freshwater 8
    '#f28f84',// croplan 9
    '#ff0000'// urban 10
    ]
}
Map.addLayer(ecoTypes, vizParams, 'eco types')


// ------- Sentinel-2 NDVI -----------------------------------------------------------
var sentinel2 = ee.ImageCollection('COPERNICUS/S2_SR')
  .filterDate('2019-01-01', '2020-01-01')
  .filterBounds(aoi)
  .filterMetadata('CLOUDY_PIXEL_PERCENTAGE', 'less_than', 30)
  .map(maskS2clouds)
  .select(['B2','B3','B4','B8', 'B11','B12'],
          ['blue', 'green', 'red','nir','swir1', 'swir2'])
  .map(addIndices);
  
// Clean duplicate images
sentinel2 = dailyMosaics(sentinel2);

var ndvi = sentinel2.select('ndvi').median();

Map.addLayer(ndvi, {min:0, max:1, palette:['white','yellow','green']}, 'ndvi')


// ------- Terrain elevation -----------------------------------------------------------
var dtm10 = ee.Image("users/rangelandee/NINA/Raster/Fenoscandia_DTM_10m");
var elevation = dtm10.unmask(0).rename('elevation');
Map.addLayer(elevation, {min:0, max:400}, 'elevation');


// ------- Trail density -------------------------------------------------------------
var trailImg = ee.Image(0).byte().paint(osm, 1);
trailImg = trailImg.reproject(dtm10.projection().atScale(10))
// density within 250m of each trail
  // can define larger distance, but may cause memory issues with GEE
  // then you should first export the image to Asset, then re-import and continue the extraction
var trailDens = trailImg.reduceNeighborhood(ee.Reducer.mean(), ee.Kernel.circle(250, 'meters')).rename('trail_dens');
trailDens = trailDens.rename('trailDens')
Map.addLayer(trailDens, {min:0, max:0.5, palette:['white','blue','black']}, 'trailDens')


/*
  // Extract and export data //////////////////////////////////////////////////////////////////////////
*/

// Stack continuous environmental variables
var outStackContinuous = ndvi
  .addBands(elevation)
  .addBands(trailDens);
outStackContinuous = outStackContinuous.clip(aoi);

// Extract continuous variables  -mean for each trail geometry
var tableContinuous = outStackContinuous.reduceRegions({
  collection: osm, 
  reducer: ee.Reducer.mean(), 
  scale: 30, 
  tileScale: 4
});
tableContinuous = tableContinuous.map(function(ft){return ft.setGeometry(null)});
print(tableContinuous.limit(10))

// Submit export task - open "Tasks" panel on right and click "Run"
Export.table.toDrive({
  collection: tableContinuous,
  description: 'explan_vars_continuous',
  fileFormat: 'CSV'
})

// Extract categorical variables  -mode for each trail geometry
var tableCategorical = ecoTypes.reduceRegions({
  collection: osm, 
  reducer: ee.Reducer.mode(), 
  scale: 20
});
tableCategorical = tableCategorical.map(function(ft){return ft.setGeometry(null)});
print(tableCategorical.limit(10))

// Submit export task - open "Tasks" panel on right and click "Run"
Export.table.toDrive({
  collection: tableCategorical,
  description: 'explan_vars_categorical',
  fileFormat: 'CSV'
})