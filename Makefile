.PHONY: send get csv tab zip

put:
	#git commit -am auto
	cp -f ./GuildSalesQuota.lua /Volumes/Elder\ Scrolls\ Online/live/AddOns/GuildSalesQuota/

get:
	cp -f /Volumes/Elder\ Scrolls\ Online/live/SavedVariables/GuildSalesQuota.lua ../../SavedVariables/
	cp -f ../../SavedVariables/GuildSalesQuota.lua data/

csv: data/GuildSalesQuota.lua
	lua GuildSalesQuota_to_csv.lua

tab: ../../SavedVariables/GuildSalesQuota.lua
	lua GuildSalesQuota_to_csv.lua --tab | pbcopy
	# Copied to clipboard. Paste somewhere useful.

zip:
	-rm -rf published/GuildSalesQuota published/GuildSalesQuota\ x.x.x.x.zip
	mkdir -p published/GuildSalesQuota
	cp -R Libs published/GuildSalesQuota/Libs
	cp ./GuildSalesQuota* published/GuildSalesQuota/
	cd published; zip -r GuildSalesQuota\ x.x.x.x.zip GuildSalesQuota

