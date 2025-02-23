# |  (C) 2008-2021 Potsdam Institute for Climate Impact Research (PIK)
# |  authors, and contributors see CITATION.cff file. This file is part
# |  of MAgPIE and licensed under AGPL-3.0-or-later. Under Section 7 of
# |  AGPL-3.0, you are granted additional permissions described in the
# |  MAgPIE License Exception, version 1.0 (see LICENSE file).
# |  Contact: magpie@pik-potsdam.de

# --------------------------------------------------------------
# description: run simulations for calculation of MAgPIE emulators
# ---------------------------------------------------------------


#########################################################
#### Start MAgPIE runs to derive price emulator from ####
#########################################################

library(gms)
library(magpie4)
library(txtplot)
library(lucode2)

source("scripts/start_functions.R")
source("config/default.cfg")

###############################################################
##################### General settings ########################
###############################################################

cfg$results_folder  <- "output/:title:"
cfg$output          <- c("report","emulator") #unique(c(cfg$output,"remind","bioenergy","coupling_report","david"))

# use old regions: c30c1c580039c2b300d86cc46ff4036a
# use H12 regions: 690d3718e151be1b450b394c1064b1c5
#cfg$input <- c("isimip_rcp-IPSL_CM5A_LR-rcp2p6-noco2_rev29_h200_690d3718e151be1b450b394c1064b1c5.tgz",
#               "rev3.15_690d3718e151be1b450b394c1064b1c5_magpie.tgz",
#               "rev3.15_690d3718e151be1b450b394c1064b1c5_validation.tgz",
#               "additional_data_rev3.28.tgz",
#               "npi_ndc_base_SSP2_fixed.tgz")

# Download bioenergy demand scenarios
filemap <- gms::download_unpack(input="emulator.tgz", targetdir="input", repositories=list("/p/projects/landuse/data/input/archive"=NULL), debug=FALSE)
d <- readRDS("input/emulator.Rdata")
demand <- time_interpolate(d,interpolated_year=seq(1995,2100,5),extrapolation_type="constant")
getSets(demand) <- getSets(d)
# add years after 2100
demand <- add_columns(demand,dim = 2.1,addnm = c("y2110","y2130","y2150"))
# keep demand constant after 2100
demand[,c("y2110","y2130","y2150"),] <- setYears(demand[,"y2100",])

#reg <- read.csv2(cfg$regionmapping) # read regional resolution, used for ghg tax
reg <- list(RegionCode = "GLO")

scenarios <- read.csv2("config/scenario_config_emulator.csv",strip.white=TRUE,stringsAsFactors=FALSE)
scenarios <- subset(scenarios, subset=(start == "1"))

###############################################################
######################## Functions ############################
###############################################################

# calculate expoLinear tax with transition in 2060
write.ghgtax <- function(co2tax_2025=NULL,regions=NULL,out="./modules/56_ghg_policy/input/f56_pollutant_prices_emulator.cs3") {

  fname <- paste0(scenarios[scen,"co2tax_2025"],".mif")

  if (file.exists(fname)) {

    # If there is a REMIND report with the name, read the GHG prices from the file, otherwise calculate expo-linear tax
    cat("Loading CO2 prices from",fname,"\n")
    tmp <- read.report(fname, as.list = FALSE)

    # Select variables from REMIND report
    ghg_price_names <- c("Price|Carbon (US$2005/t CO2)",
                         "Price|N2O (US$2005/t N2O)",
                         "Price|CH4 (US$2005/t CH4)")
    tmp <- collapseNames(tmp[,,ghg_price_names])
    # remove global dimension
    tmp <- tmp["GLO",,,invert=TRUE]

    # interpolate missing years (REMIND has less_TS only, emulator script need 5 year time steps)
    time <- seq(1995,2100,5)
    tmp <- time_interpolate(tmp,interpolated_year=time,extrapolation_type="constant")

    ghgtax <- new.magpie(cells_and_regions = getRegions(tmp),years = time,fill = NA,sets = c("regions","years","gas"),names = c("n2o_n_direct","n2o_n_indirect","ch4","co2_c"))

    # unit defined in modules/56_ghg_policy/input/f56_pollutant_prices.cs3: US$ 2005 per Mg N2O-N CH4 and CO2-C
    ghgtax[,,"co2_c"]          <- tmp[,,"Price|Carbon (US$2005/t CO2)"] * 44/12  # US$2005/tCO2 -> US$2005/tC
    ghgtax[,,"ch4"]            <- tmp[,,"Price|CH4 (US$2005/t CH4)"]
    ghgtax[,,"n2o_n_direct"]   <- tmp[,,"Price|N2O (US$2005/t N2O)"] * 44/28     # US$2005/tN2O -> US$2005/tN
    ghgtax[,,"n2o_n_indirect"] <- tmp[,,"Price|N2O (US$2005/t N2O)"] * 44/28     # US$2005/tN2O -> US$2005/tN

  } else {
  
    stop("Could not find ", fname)

    # Calculate expo-linear tax

    if(is.null(co2tax_2025)) stop("No initial value for ghg tax supplied.")
    if(is.null(regions))     stop("Please supply regions for ghg tax.")

    # construct combination of exponential tax (5% increase) until 2050 and linear continuation thereafter (using the slope of 2045-2050)
    time <- seq(1995,2100,5)
    co2tax <- as.numeric(co2tax_2025) * 1.05 ^(time-2025)
    names(co2tax)<-time
    slope <- (co2tax["2050"] - co2tax["2045"]) / (2050 - 2045)
    co2tax[names(co2tax)>"2050"] <- co2tax["2050"] + slope * (time[time>2050] - 2050)

    ghgtax <- new.magpie(cells_and_regions = regions,years = time,fill = NA,sets = c("regions","years","gas"),names = c("n2o_n_direct","n2o_n_indirect","ch4","co2_c"))

    # unit defined in modules/56_ghg_policy/input/f56_pollutant_prices.cs3: US$ 2005 per Mg N2O-N CH4 and CO2-C
    ghgtax[,,"co2_c"]          <- as.magpie(co2tax) * 44/12       # US$2005/tCO2 -> US$2005/tC
    ghgtax[,,"ch4"]            <- as.magpie(co2tax) * 28          # US$2005/tCO2 -> US$2005/tCH4 (using Global Warming Potentials from AR5 WG1 CH08 Table 8.7)
    ghgtax[,,"n2o_n_direct"]   <- as.magpie(co2tax) * 44/28 * 265 # US$2005/tCO2 -> US$2005/tN (using Global Warming Potentials from AR5 WG1 CH08 Table 8.7)
    ghgtax[,,"n2o_n_indirect"] <- as.magpie(co2tax) * 44/28 * 265 # US$2005/tCO2 -> US$2005/tN (using Global Warming Potentials from AR5 WG1 CH08 Table 8.7)

  }

  # set ghg prices before and in 2020 to zero
  ghgtax[,getYears(ghgtax)<="y2020",] <- 0
  # add years after 2100
  ghgtax <- add_columns(ghgtax,dim = 2.1,addnm = c("y2110","y2130","y2150"))
  # keep ghgtax constant after 2100
  ghgtax[,c("y2110","y2130","y2150"),] <- setYears(ghgtax[,"y2100",])

  # create textplot
  cat("CO2 price in 2025:",ghgtax[,2025,"co2_c"],"\n")
  for_plot <- ghgtax[1,,"co2_c"] * 12/44 # convert unit back just for plotting
  #for_plot <- for_plot[,c("y1995","y2110","y2130","y2150"),,invert=TRUE]
  txtplot(as.numeric(gsub("y","",getYears(for_plot))),for_plot,ylab="US$2005/tCO2")

  cat("Writing GHG tax scenario",scenarios[scen,"co2tax_name"],"\n\n")
  write.magpie(ghgtax,file_name = out)

  #library(ggplot2)
  #library(luplot)
  #ggplot(gginput(as.magpie(co2tax)), aes(x=year, y=.value)) + geom_line()
}

###############################################################
################# Individual scenarios ########################
###############################################################

for (scen in rownames(scenarios)) {

  cat("\n################ Scenario",scen,"################\n")
  # Configure MAgPIE
  # Set scenario
  cfg<-setScenario(cfg,scenario = c(trimws(unlist(strsplit(scenarios[scen,"mag_scen"],split=",")))))
  # emulator has to be set AFTER SSP because SSP would set bioenergy demand to predefined scenario and not to input from this script
  cfg<-setScenario(cfg,scenario="emulator")

  # Choose GHG tax scenario
  if (scenarios[scen,"co2tax_2025"] == "built-in") {
    # see magpie/config/default.cfg for available scenarios
    cfg$gms$c56_pollutant_prices <- scenarios[scen,"co2tax_name"]
  } else {
    # If none of the built-in GHG price scenarios was chosen, provide GHG prices
    cfg$gms$c56_pollutant_prices <- "emulator"
    write.ghgtax(co2tax_2025=scenarios[scen,"co2tax_2025"],regions=unique(reg$RegionCode))
  }

  # Compose string with scenario name
  expname <- paste0(gsub(",","-",scenarios[scen,"mag_scen"]),"-",scenarios[scen,"co2tax_name"])

  # run numbers sorted in descending by runtime (taken from former SSP2-26 emulator runs)
  runtime_order <- c("4","17","34","12","11","22","32","15","21","2","58","18","20","16","19",
  "31","67","41","48","54","65","47","13","44","70","28","52","53","62","36","40","9","14","46",
  "10","29","38","71","57","50","60","37","64","69","68","51","61","5","27","7","66","6","49",
  "35","45","59","56","24","72","25","63","42","30","1","55","43","26","3","39","73","23","33","8")
  # the intersect command in the for-loop below keeps the order of the vector given first

  # Copy bioenergy demand files and start runs
  for(r in intersect(runtime_order,getNames(demand))) {
  #for(r in as.character(c(1))) {
    cfg$title <- paste(expname,r,sep="-")
    cat(cfg$title,"Writing bioenergy demand scenario",r,"\n")
    # create text plot
    dem <- dimSums(demand[,,r],dim=1)
    for_plot <- dem/1000
    #for_plot <- for_plot[,c("y1995","y2110","y2130","y2150"),,invert=TRUE]
    txtplot(as.numeric(gsub("y","",getYears(for_plot))),for_plot,ylab="EJ/yr")
    write.magpie(setNames(dem,NULL), file_name = "./modules/60_bioenergy/input/glo.2ndgen_bioenergy_demand.csv")
    manipulateConfig("scripts/run_submit/submit.sh","--job-name"=cfg$title,line_endings = "NOTwin")
    start_run(cfg,codeCheck=FALSE)
  }
}

cat("Finished starting of emulator runs!\n")
