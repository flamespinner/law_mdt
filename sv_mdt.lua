local VorpCore = {}
VORP = exports.vorp_core:vorpAPI()

TriggerEvent("getCore",function(core)
    VorpCore = core
end)

RegisterCommand("mdt", function(source, args)
    local _source = source
    local Character = VorpCore.getUser(_source).getUsedCharacter
    local job = Character.job
	local jobgrade = Character.jobGrade
	local officername = (Character.firstname.. " " ..Character.lastname)

	if job == 'police' or 'ranger' then
		exports.ghmattimysql:execute("SELECT * FROM (SELECT * FROM `mdt_reports` ORDER BY `id` DESC LIMIT 3) sub ORDER BY `id` DESC", {}, function(reports)
    		for r = 1, #reports do
    			reports[r].charges = json.decode(reports[r].charges)
    		end
    		exports.ghmattimysql:execute("SELECT * FROM (SELECT * FROM `mdt_warrants` ORDER BY `id` DESC LIMIT 3) sub ORDER BY `id` DESC", {}, function(warrants)
    			for w = 1, #warrants do
    				warrants[w].charges = json.decode(warrants[w].charges)
    			end

    			TriggerClientEvent('law_mdt:toggleVisibilty', _source, reports, warrants, officername, job, jobgrade)
    		end)
    	end)
	end
end)

RegisterServerEvent("law_mdt:getOffensesAndOfficer")
AddEventHandler("law_mdt:getOffensesAndOfficer", function()
	local usource = source
	local Character = VorpCore.getUser(usource).getUsedCharacter
	local officername = (Character.firstname.. " " ..Character.lastname)

	local charges = {}
	exports.ghmattimysql:execute('SELECT * FROM fine_types', {}, function(fines)
		for j = 1, #fines do
			if fines[j].category == 0 or fines[j].category == 1 or fines[j].category == 2 or fines[j].category == 3 then
				table.insert(charges, fines[j])
			end
		end

		TriggerClientEvent("law_mdt:returnOffensesAndOfficer", usource, charges, officername)
	end)
end)

RegisterServerEvent("law_mdt:performOffenderSearch")
AddEventHandler("law_mdt:performOffenderSearch", function(query)
	local usource = source
	local matches = {}

	exports.ghmattimysql:execute("SELECT * FROM `characters` WHERE LOWER(`firstname`) LIKE @query OR LOWER(`lastname`) LIKE @query OR CONCAT(LOWER(`firstname`), ' ', LOWER(`lastname`)) LIKE @query", {
		['@query'] = string.lower('%'..query..'%')
	}, function(result)

		for index, data in ipairs(result) do
			table.insert(matches, data)
		end

		TriggerClientEvent("law_mdt:returnOffenderSearchResults", usource, matches)
	end)
end)

RegisterServerEvent("law_mdt:getOffenderDetails")
AddEventHandler("law_mdt:getOffenderDetails", function(offender)
	local usource = source

	--print(offender.charidentifier)

    exports.ghmattimysql:execute('SELECT * FROM `user_mdt` WHERE `char_id` = ?', {offender.charidentifier}, function(result)

		if result[1] then
            offender.notes = result[1].notes
            offender.mugshot_url = result[1].mugshot_url
            offender.bail = result[1].bail
		else
			offender.notes = ""
			offender.mugshot_url = ""
			offender.bail = false
		end

        exports.ghmattimysql:execute('SELECT * FROM `user_convictions` WHERE `char_id` = ?', {offender.charidentifier}, function(convictions)

            if convictions[1] then
                offender.convictions = {}
                for i = 1, #convictions do
                    local conviction = convictions[i]
                    offender.convictions[conviction.offense] = conviction.count
                end
            end

            exports.ghmattimysql:execute('SELECT * FROM `mdt_warrants` WHERE `char_id` = ?', {offender.charidentifier}, function(warrants)

                if warrants[1] then
                    offender.haswarrant = true
                end
			
				TriggerClientEvent("law_mdt:returnOffenderDetails", usource, offender)
            end)
        end)
    end)
end)

RegisterServerEvent("law_mdt:getOffenderDetailsById")
AddEventHandler("law_mdt:getOffenderDetailsById", function(char_id)
    local usource = source
	print(char_id)

    exports.ghmattimysql:execute('SELECT * FROM `characters` WHERE `charidentifier` = ?', {char_id}, function(result)

        local offender = result[1]

        if not offender then
            TriggerClientEvent("law_mdt:closeModal", usource)
            TriggerClientEvent("law_mdt:sendNotification", usource, "This person no longer exists.")
            return
        end
    
        exports.ghmattimysql:execute('SELECT * FROM `user_mdt` WHERE `char_id` = ?', {char_id}, function(result)

			if result[1] then
                offender.notes = result[1].notes
                offender.mugshot_url = result[1].mugshot_url
                offender.bail = result[1].bail
			else
				offender.notes = ""
				offender.mugshot_url = ""
				offender.bail = false
			end

            exports.ghmattimysql:execute('SELECT * FROM `user_convictions` WHERE `char_id` = ?', {char_id}, function(convictions) 

                if convictions[1] then
                    offender.convictions = {}
                    for i = 1, #convictions do
                        local conviction = convictions[i]
                        offender.convictions[conviction.offense] = conviction.count
                    end
                end

                exports.ghmattimysql:execute('SELECT * FROM `mdt_warrants` WHERE `char_id` = ?', {char_id}, function(warrants)
                    
                    if warrants[1] then
                        offender.haswarrant = true
                    end

					TriggerClientEvent("law_mdt:returnOffenderDetails", usource, offender)
                end)
            end)
        end)
    end)
end)

RegisterServerEvent("law_mdt:saveOffenderChanges")
AddEventHandler("law_mdt:saveOffenderChanges", function(charidentifier, changes, identifier)
	local usource = source

	exports.ghmattimysql:execute('SELECT * FROM `user_mdt` WHERE `char_id` = ?', {charidentifier}, function(result)
		if result[1] then
			exports.oxmysql:execute('UPDATE `user_mdt` SET `notes` = ?, `mugshot_url` = ?, `bail` = ? WHERE `char_id` = ?', {changes.notes, changes.mugshot_url, changes.bail, charidentifier})
		else
			exports.oxmysql:insert('INSERT INTO `user_mdt` (`char_id`, `notes`, `mugshot_url`, `bail`) VALUES (?, ?, ?, ?)', {charidentifier, changes.notes, changes.mugshot_url, changes.bail})
		end

		if changes.convictions ~= nil then
			for conviction, amount in pairs(changes.convictions) do	
				exports.oxmysql:execute('UPDATE `user_convictions` SET `count` = ? WHERE `char_id` = ? AND `offense` = ?', {charidentifier, amount, conviction})
			end
		end

		for i = 1, #changes.convictions_removed do
			exports.oxmysql:execute('DELETE FROM `user_convictions` WHERE `char_id` = ? AND `offense` = ?', {charidentifier, changes.convictions_removed[i]})
		end

		TriggerClientEvent("law_mdt:sendNotification", usource, "Offender changes have been saved.")
	end)
end)

RegisterServerEvent("law_mdt:saveReportChanges")
AddEventHandler("law_mdt:saveReportChanges", function(data)
	exports.oxmysql:execute('UPDATE `mdt_reports` SET `title` = ?, `incident` = ? WHERE `id` = ?', {data.id, data.title, data.incident})
	TriggerClientEvent("law_mdt:sendNotification", source, "Report changes have been saved.")
end)

RegisterServerEvent("law_mdt:deleteReport")
AddEventHandler("law_mdt:deleteReport", function(id)
	exports.oxmysql:execute('DELETE FROM `mdt_reports` WHERE `id` = ?', {id})
	TriggerClientEvent("law_mdt:sendNotification", source, "Report has been successfully deleted.")
end)

RegisterServerEvent("law_mdt:submitNewReport")
AddEventHandler("law_mdt:submitNewReport", function(data)
	local usource = source
	local Character = VorpCore.getUser(usource).getUsedCharacter
	local officername = (Character.firstname.. " " ..Character.lastname)

	charges = json.encode(data.charges)
	data.date = os.date('%m-%d-%Y %H:%M:%S', os.time())
	exports.oxmysql:insert('INSERT INTO `mdt_reports` (`char_id`, `title`, `incident`, `charges`, `author`, `name`, `date`) VALUES (?, ?, ?, ?, ?, ?, ?)', {data.char_id, data.title, data.incident, charges, officername, data.name, data.date,}, function(id)
		TriggerEvent("law_mdt:getReportDetailsById", id, usource)
		TriggerClientEvent("law_mdt:sendNotification", usource, "A new report has been submitted.")
	end)

	for offense, count in pairs(data.charges) do
		exports.ghmattimysql:execute('SELECT * FROM `user_convictions` WHERE `offense` = ? AND `char_id` = ?', {offense, data.char_id}, function(result)
			if result[1] then
				exports.oxmysql:execute('UPDATE `user_convictions` SET `count` = ? WHERE `offense` = ? AND `char_id` = ?', {data.char_id, offense, count + 1})
			else
				exports.oxmysql:insert('INSERT INTO `user_convictions` (`char_id`, `offense`, `count`) VALUES (?, ?, ?)', {data.char_id, offense, count})
			end
		end)
	end
end)

RegisterServerEvent("law_mdt:performReportSearch")
AddEventHandler("law_mdt:performReportSearch", function(query)
	local usource = source
	local matches = {}
	exports.ghmattimysql:execute("SELECT * FROM `mdt_reports` WHERE `id` LIKE @query OR LOWER(`title`) LIKE @query OR LOWER(`name`) LIKE @query OR LOWER(`author`) LIKE @query or LOWER(`charges`) LIKE @query", {
		['@query'] = string.lower('%'..query..'%') -- % wildcard, needed to search for all alike results
	}, function(result)

		for index, data in ipairs(result) do
			data.charges = json.decode(data.charges)
			table.insert(matches, data)
		end

		TriggerClientEvent("law_mdt:returnReportSearchResults", usource, matches)
	end)
end)

RegisterServerEvent("law_mdt:getWarrants")
AddEventHandler("law_mdt:getWarrants", function()
	local usource = source
	exports.ghmattimysql:execute("SELECT * FROM `mdt_warrants`", {}, function(warrants)
		for i = 1, #warrants do
			warrants[i].expire_time = ""
			warrants[i].charges = json.decode(warrants[i].charges)
		end
		TriggerClientEvent("law_mdt:returnWarrants", usource, warrants)
	end)
end)

RegisterServerEvent("law_mdt:submitNewWarrant")
AddEventHandler("law_mdt:submitNewWarrant", function(data)
	local usource = source
	local Character = VorpCore.getUser(usource).getUsedCharacter
	local officername = (Character.firstname.. " " ..Character.lastname)

	data.charges = json.encode(data.charges)
	data.author = officername
	data.date = os.date('%m-%d-%Y %H:%M:%S', os.time())
	exports.oxmysql:insert('INSERT INTO `mdt_warrants` (`name`, `char_id`, `report_id`, `report_title`, `charges`, `date`, `expire`, `notes`, `author`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)', {data.name, data.char_id, data.report_id, data.report_title, data.charges, data.date, data.expire, data.notes, data.author}, function()
		TriggerClientEvent("law_mdt:completedWarrantAction", usource)
		TriggerClientEvent("law_mdt:sendNotification", usource, "A new warrant has been created.")
	end)
end)

RegisterServerEvent("law_mdt:deleteWarrant")
AddEventHandler("law_mdt:deleteWarrant", function(id)
	local usource = source
	exports.oxmysql:execute('DELETE FROM `mdt_warrants` WHERE `id` = ?', {id}, function()
		TriggerClientEvent("law_mdt:completedWarrantAction", usource)
	end)
	TriggerClientEvent("law_mdt:sendNotification", usource, "Warrant has been successfully deleted.")
end)

RegisterServerEvent("law_mdt:getReportDetailsById")
AddEventHandler("law_mdt:getReportDetailsById", function(query, _source)
	if _source then source = _source end
	local usource = source
	exports.ghmattimysql:execute("SELECT * FROM `mdt_reports` WHERE `id` = ?", {query}, function(result)
		if result and result[1] then
			result[1].charges = json.decode(result[1].charges)
			TriggerClientEvent("law_mdt:returnReportDetails", usource, result[1])
		else
			TriggerClientEvent("law_mdt:closeModal", usource)
			TriggerClientEvent("law_mdt:sendNotification", usource, "This report cannot be found.")
		end
	end)
end)
