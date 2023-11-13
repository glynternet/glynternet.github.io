---
layout: page
title: Garmin Head Unit and Basecamp Maps
permalink: /cycling/maps
tags: cycling
---

### Pre-compiled
[gmaptool.eu](https://gmaptool.eu/en/content/usa-osm-topo-routable) provide pre-compiled OpenTopo maps for large areas, including the US (which seems to be a rarity).

### Bring/build your own

After moving to the US I found it hard to find a place that provided map tiles that are supported in BaseCamp.

Ended up finding the dev process for [freizeitkarte](https://www.freizeitkarte-osm.de/) in their [Github Repo](https://github.com/freizeitkarte/fzk-mde-garmin/blob/develop/Freizeitkarte-Entwicklung/readme_EN.txt) and folling it.
Some more info on the process at https://www.freizeitkarte-osm.de/garmin/en/development.html.

To build a `.gmap`, an expected directory structure, for BaseCamp, do the following, then move the `.gmap` into the BaseCamp Maps directory.

Supported out-the-box regions for their tooling can be found [here](https://github.com/freizeitkarte/fzk-mde-garmin/blob/7b3f594a1824c9b7576cb87b23eb127d1b726065/Freizeitkarte-Entwicklung/mt.pl#L189).

It may well be possible to create a custom shape and feed it into their system but I did not end up trying this.

On Linux:
Each step can take a while, overall process took approx 90 minutes for the US WEST region.
```shell
region=Freizeitkarte_US_WEST
ram="--ram=16384"
cores="--cores=max"
perl mt.pl create $ram $cores $region
perl mt.pl fetch_osm $ram $cores $region
perl mt.pl fetch_ele $ram $cores $region
perl mt.pl join $ram $cores $region
perl mt.pl split $ram $cores $region
perl mt.pl build $ram $cores $region
perl mt.pl gmap $ram $cores $region

### Optional: for windows installer, not needed but I did try it.
# nsis only supports up to 2GB
perl mt.pl nsis $ram $cores $region
```