##EDIT ME - constant variables##
#location of folder for lidar tile files, downloaded from https://apps.nationalmap.gov/lidar-explorer/#/
LIDAR_FILEPATH <- "lidar_files"
#location of NDVI raster file, downloaded from https://registry.opendata.aws/naip/
NDVI_FILEPATH <- "NAIP_NDVIaggregate_median_2019_pt6mscale_test.tif"



##Setup libraries##
#lidR documentation: https://r-lidar.github.io/lidRbook/itd-its.html#itd

#specify the packages of interest
packages = c("tidyverse","lubridate","rgdal","raster","sf","lidR","remotes","maptools", "terra")

#use this function to check if each package is on the local machine
#if a package is installed, it will be loaded
#if any are not, the missing package(s) will be installed and loaded
package.check <- lapply(packages, FUN = function(x) {
  if (!require(x, character.only = TRUE)) {
    install.packages(x, dependencies = TRUE)
    library(x, character.only = TRUE)
  }
})
rm(package.check);rm(packages)



##Generate Canopy Height Model##
#read NDVI
ndvi <- raster(NDVI_FILEPATH)

#read and check collection of LIDAR tiles stored in the folder at lidar_filepath
ctg <- readLAScatalog(LIDAR_FILEPATH)
las_check(ctg)

#clip ctg to extent of ndvi to ensure only analzying within city limits
ctg_clipped <- clip_roi(ctg, ndvi@extent)

#Digital Surface Model -- DSM -- the "top layer" of lidar points - includes natural and human-made structures
#0.6 is res of NDVI
dsm_catalog <- rasterize_canopy(ctg, res = 0.6, pkg = "terra")

#Digital Elevation Model -- DEM -- Bare Earth/terrain model
#similar function, filters lidar points that are classified as ground
dem_catalog <- rasterize_terrain(ctg, res = 0.6, pkg = "terra")

#Canopy Height Model -- CHM -- DSM that is height/elevation normalized
chm_catalog <- dsm_catalog - dem_catalog

#Set any height values that are negative to zero
chm_catalog[chm_catalog < 0] <- 0

chm_catalog_tree <- chm_catalog

#Filter CHM so that anything that is not a tree is set to zero height. This will exclude non-trees from the tree detection function.
#These filtering criteria could potentially be modified if it seems like a lot of trees are getting missed.
#Filtering for heights less than 1.5 meters
chm_catalog_tree[chm_catalog_tree < 1.5] <- 0

#Filter for NDVI values less than 0.2
chm_catalog_tree_raster <- raster(chm_catalog_tree)
chm_catalog_tree_raster[ndvi_crop < .2] <- 0

# Save the data
writeRaster(chm_catalog_tree, "chm_catalog_tree.tif", overwrite=TRUE)



##Individual Tree Detection##

#this function generally OVERCOUNTS trees. Trees that appear to be missing likely aren't present in the LIDAR data.
#lmf() is the function that determines the window size used to detect trees
#more info on window size in this section: https://r-lidar.github.io/lidRbook/itd-its.html#itd
#small window size means more trees, while large window size generally misses smaller trees that are “hidden” by big trees that contain the highest points in the neighbourhood.
#this function was experimented with quite a bit and a constant window of size 6m was found to give the most accurate results, but this could be adjusted further. variable window sizes are also possible, see examples in above documentation
ttops <- locate_trees(chm_catalog_tree, lmf(6))

#write out as shapefile to look at in GIS software
#locate_trees output 3D points, st_zm removes the "Z" component of the geometry, necessary to save as shapefile. However height data (the Z component), is preserved in the data as its own column
write_sf(st_zm(ttops),"treetops.shp")



##Crown Segmentation##
#this function uses both the CHM and the tree locations from locate_trees
crowns <- dalponte2016(chm_catalog_tree, ttops)()

#output
writeRaster(crowns, "crowns.tif")



##NONFUNCTIONAL - download files##
#downloads files successfully, but corrupts them in some way that makes them unusuble for lidR
#note the ranges for i and j that form the boundary for the City of Phoenix

for (i in 375:420){ # full range: 375 to 420
  for (j in 3684:3747){ # full range: from 3684 to 3747
    name <- paste0("lidar_files/0", i, "_", j, ".laz")
    url <- paste0("https://rockyweb.usgs.gov/vdelivery/Datasets/Staged/Elevation/LPC/Projects/AZ_MaricopaPinal_2020_B20/AZ_MaricopaPinal_1_2020/LAZ/USGS_LPC_AZ_MaricopaPinal_2020_B20_w0", i, "n", j, ".laz")
    download.file(url, destfile = name)
  }
}
