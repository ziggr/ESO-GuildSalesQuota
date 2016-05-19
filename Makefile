.PHONY: send get csv

put:
	git commit -am auto
	cp -f ./GuildSalesQuota.lua /Volumes/Elder\ Scrolls\ Online/live/AddOns/GuildSalesQuota/

get:
	cp -f /Volumes/Elder\ Scrolls\ Online/live/SavedVariables/GuildSalesQuota.lua ../../SavedVariables/
	cp -f ../../SavedVariables/GuildSalesQuota.lua data/

csv: ../../SavedVariables/GuildSalesQuota.lua
	lua GuildSalesQuota_to_csv.lua
	cp -f ../../SavedVariables/GuildSalesQuota.csv data/

zip:
	-rm -rf published/GuildSalesQuota published/GuildSalesQuota\ x.x.x.x.zip
	mkdir -p published/GuildSalesQuota
	cp -R Libs published/GuildSalesQuota/Libs
	cp ./GuildSalesQuota* published/GuildSalesQuota/
	cd published; zip -r GuildSalesQuota\ x.x.x.x.zip GuildSalesQuota

