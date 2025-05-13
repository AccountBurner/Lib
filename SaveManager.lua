local cloneref = cloneref or function(o) return o end
local httpService = cloneref(game:GetService('HttpService'))
local marketplaceService = cloneref(game:GetService('MarketplaceService'))

if copyfunction and isfolder then
	local isfolder_, isfile_, listfiles_ = copyfunction(isfolder), copyfunction(isfile), copyfunction(listfiles)
	local success_, error_ = pcall(function() return isfolder_(tostring(math.random(999999999, 999999999999))) end)

	if success_ == false or (tostring(error_):match("not") and tostring(error_):match("found")) then
		getgenv().isfolder = function(folder)
			local s, data = pcall(function() return isfolder_(folder) end)
			if s == false then return nil end
			return data
		end
	
		getgenv().isfile = function(file)
			local s, data = pcall(function() return isfile_(file) end)
			if s == false then return nil end
			return data
		end
	
		getgenv().listfiles = function(folder)
			local s, data = pcall(function() return listfiles_(folder) end)
			if s == false then return {} end
			return data
		end
	end
end

local SaveManager = {}

SaveManager.Folder = 'LinoriaLibSettings'
SaveManager.Ignore = {}
SaveManager.ConfigHistory = {}
SaveManager.MaxBackups = 10
SaveManager.MaxHistory = 50

SaveManager.Parser = {
	Toggle = {
		Save = function(idx, object) 
			return { type = 'Toggle', idx = idx, value = object.Value } 
		end,
		Load = function(idx, data)
			if getgenv().Linoria.Toggles[idx] then 
				getgenv().Linoria.Toggles[idx]:SetValue(data.value)
			end
		end,
	},
	Slider = {
		Save = function(idx, object)
			return { type = 'Slider', idx = idx, value = tostring(object.Value) }
		end,
		Load = function(idx, data)
			if getgenv().Linoria.Options[idx] then 
				getgenv().Linoria.Options[idx]:SetValue(data.value)
			end
		end,
	},
	Dropdown = {
		Save = function(idx, object)
			return { type = 'Dropdown', idx = idx, value = object.Value, multi = object.Multi }
		end,
		Load = function(idx, data)
			if getgenv().Linoria.Options[idx] then 
				getgenv().Linoria.Options[idx]:SetValue(data.value)
			end
		end,
	},
	ColorPicker = {
		Save = function(idx, object)
			return { type = 'ColorPicker', idx = idx, value = object.Value:ToHex(), transparency = object.Transparency }
		end,
		Load = function(idx, data)
			if getgenv().Linoria.Options[idx] then 
				getgenv().Linoria.Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency)
			end
		end,
	},
	KeyPicker = {
		Save = function(idx, object)
			return { type = 'KeyPicker', idx = idx, mode = object.Mode, key = object.Value }
		end,
		Load = function(idx, data)
			if getgenv().Linoria.Options[idx] then 
				getgenv().Linoria.Options[idx]:SetValue({ data.key, data.mode })
			end
		end,
	},
	Input = {
		Save = function(idx, object)
			return { type = 'Input', idx = idx, text = object.Value }
		end,
		Load = function(idx, data)
			if getgenv().Linoria.Options[idx] and type(data.text) == 'string' then
				getgenv().Linoria.Options[idx]:SetValue(data.text)
			end
		end,
	},
}

function SaveManager:GetConfigMetadata(name)
	local file = self.Folder .. '/settings/' .. name .. '.meta'
	if isfile(file) then
		local success, data = pcall(httpService.JSONDecode, httpService, readfile(file))
		if success then return data end
	end
	return {}
end

function SaveManager:SaveConfigMetadata(name, metadata)
	local file = self.Folder .. '/settings/' .. name .. '.meta'
	metadata.lastModified = os.time()
	local success, gameInfo = pcall(function()
		return marketplaceService:GetProductInfo(game.PlaceId).Name
	end)
	metadata.gameName = success and gameInfo or 'Unknown'
	metadata.gameId = game.PlaceId
	local success, encoded = pcall(httpService.JSONEncode, httpService, metadata)
	if success then
		writefile(file, encoded)
	end
end

function SaveManager:CheckFolderTree()
	pcall(function()
		if not isfolder(self.Folder) then
			SaveManager:BuildFolderTree()
			task.wait()
		end
	end)
end

function SaveManager:SetIgnoreIndexes(list)
	for _, key in next, list do
		self.Ignore[key] = true
	end
end

function SaveManager:SetFolder(folder)
	self.Folder = folder
	self:BuildFolderTree()
end

function SaveManager:CreateBackup(name)
	self:CheckFolderTree()
	local timestamp = os.date("%Y%m%d_%H%M%S")
	local backupName = name .. '_backup_' .. timestamp
	local backupPath = self.Folder .. '/backups/' .. backupName .. '.json'
	
	if not isfolder(self.Folder .. '/backups') then
		makefolder(self.Folder .. '/backups')
	end
	
	local originalPath = self.Folder .. '/settings/' .. name .. '.json'
	if isfile(originalPath) then
		local data = readfile(originalPath)
		writefile(backupPath, data)
		
		self:SaveConfigMetadata(backupName, {
			type = 'backup',
			originalName = name
		})
		
		self:CleanupOldBackups(name)
		return true, backupName
	end
	return false, 'Original config not found'
end

function SaveManager:CleanupOldBackups(configName)
	local backups = {}
	local backupFolder = self.Folder .. '/backups'
	
	if isfolder(backupFolder) then
		for _, file in pairs(listfiles(backupFolder)) do
			if file:find(configName .. '_backup_') then
				table.insert(backups, file)
			end
		end
		
		table.sort(backups)
		
		while #backups > self.MaxBackups do
			local oldest = table.remove(backups, 1)
			delfile(oldest)
			local metaFile = oldest:gsub('.json', '.meta')
			if isfile(metaFile) then
				delfile(metaFile)
			end
		end
	end
end

function SaveManager:Save(name, description)
	if not name then
		return false, 'no config file is selected'
	end
	
	self:CheckFolderTree()
	
	local fullPath = self.Folder .. '/settings/' .. name .. '.json'
	local data = {
		version = '2.0',
		created = os.time(),
		objects = {},
		metadata = {
			description = description or '',
			gameId = game.PlaceId,
		}
	}

	for idx, toggle in next, getgenv().Linoria.Toggles do
		if self.Ignore[idx] then continue end
		table.insert(data.objects, self.Parser[toggle.Type].Save(idx, toggle))
	end

	for idx, option in next, getgenv().Linoria.Options do
		if not self.Parser[option.Type] then continue end
		if self.Ignore[idx] then continue end
		table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
	end	

	local success, encoded = pcall(httpService.JSONEncode, httpService, data)
	if not success then
		return false, 'failed to encode data'
	end

	if isfile(fullPath) then
		self:CreateBackup(name)
	end

	writefile(fullPath, encoded)
	
	self:SaveConfigMetadata(name, data.metadata)
	
	self:AddToHistory('save', name)
	
	return true
end

function SaveManager:Load(name)
	if not name then
		return false, 'no config file is selected'
	end
	
	self:CheckFolderTree()
	
	local file = self.Folder .. '/settings/' .. name .. '.json'
	if not isfile(file) then 
		return false, 'invalid file' 
	end

	local rawData = readfile(file)

	local success, decoded = pcall(httpService.JSONDecode, httpService, rawData)
	if not success then 
		return false, 'decode error' 
	end

	if decoded.version and decoded.version ~= '2.0' then
		if self.Library then
			self.Library:Notify('Loading older config format...', 2)
		end
	end

	for _, option in next, decoded.objects do
		if self.Parser[option.type] then
			task.spawn(function() 
				self.Parser[option.type].Load(option.idx, option) 
			end)
		end
	end

	self:AddToHistory('load', name)

	return true
end

function SaveManager:Delete(name)
	if not name then
		return false, 'no config file is selected'
	end
	
	local file = self.Folder .. '/settings/' .. name .. '.json'
	if not isfile(file) then 
		return false, 'invalid file' 
	end

	self:CreateBackup(name)

	local success = pcall(delfile, file)
	if not success then 
		return false, 'delete file error' 
	end
	
	local metaFile = self.Folder .. '/settings/' .. name .. '.meta'
	if isfile(metaFile) then
		delfile(metaFile)
	end
	
	self:AddToHistory('delete', name)
	
	return true
end

function SaveManager:Duplicate(originalName, newName)
	if not originalName or not newName then
		return false, 'missing names'
	end
	
	local originalFile = self.Folder .. '/settings/' .. originalName .. '.json'
	if not isfile(originalFile) then
		return false, 'original file not found'
	end
	
	local newFile = self.Folder .. '/settings/' .. newName .. '.json'
	local data = readfile(originalFile)
	writefile(newFile, data)
	
	local metadata = self:GetConfigMetadata(originalName)
	metadata.duplicatedFrom = originalName
	metadata.duplicatedAt = os.time()
	self:SaveConfigMetadata(newName, metadata)
	
	self:AddToHistory('duplicate', originalName .. ' -> ' .. newName)
	
	return true
end

function SaveManager:Export(name)
	if not name then
		return false, 'no config selected'
	end
	
	local file = self.Folder .. '/settings/' .. name .. '.json'
	if not isfile(file) then
		return false, 'file not found'
	end
	
	local data = readfile(file)
	local metadata = self:GetConfigMetadata(name)
	
	local exportData = {
		name = name,
		data = data,
		metadata = metadata,
		exported = os.time()
	}
	
	local success, encoded = pcall(httpService.JSONEncode, httpService, exportData)
	if not success then
		return false, 'encoding failed'
	end
	
	if setclipboard then
		setclipboard(encoded)
		return true, 'Config exported to clipboard'
	end
	
	return false, 'Clipboard not available'
end

function SaveManager:Import(configData, newName)
	local success, decoded = pcall(httpService.JSONDecode, httpService, configData)
	if not success then
		return false, 'Invalid config data'
	end
	
	if not decoded.data or not decoded.name then
		return false, 'Malformed config'
	end
	
	local name = newName or decoded.name
	local file = self.Folder .. '/settings/' .. name .. '.json'
	
	writefile(file, decoded.data)
	
	if decoded.metadata then
		decoded.metadata.imported = os.time()
		self:SaveConfigMetadata(name, decoded.metadata)
	end
	
	self:AddToHistory('import', name)
	
	return true
end

function SaveManager:AddToHistory(action, details)
	table.insert(self.ConfigHistory, 1, {
		action = action,
		details = details,
		timestamp = os.time()
	})
	
	while #self.ConfigHistory > self.MaxHistory do
		table.remove(self.ConfigHistory)
	end
end

function SaveManager:GetHistory()
	return self.ConfigHistory
end

function SaveManager:ValidateConfig(name)
	local file = self.Folder .. '/settings/' .. name .. '.json'
	if not isfile(file) then
		return false, 'File not found'
	end
	
	local rawData = readfile(file)
	
	local success, decoded = pcall(httpService.JSONDecode, httpService, rawData)
	if not success then
		return false, 'Invalid JSON'
	end
	
	if not decoded.objects then
		return false, 'Missing objects'
	end
	
	local validCount = 0
	local totalCount = #decoded.objects
	
	for _, obj in pairs(decoded.objects) do
		if obj.type and obj.idx then
			validCount = validCount + 1
		end
	end
	
	return true, string.format('Valid (%d/%d objects)', validCount, totalCount)
end

function SaveManager:IgnoreThemeSettings()
	self:SetIgnoreIndexes({ 
		"BackgroundColor", "MainColor", "AccentColor", "OutlineColor", "FontColor",
		"ThemeManager_ThemeList", 'ThemeManager_CustomThemeList', 'ThemeManager_CustomThemeName',
		"VideoLink", "AudioLink"
	})
end

function SaveManager:BuildFolderTree()
	local paths = {
		self.Folder,
		self.Folder .. '/themes',
		self.Folder .. '/settings',
		self.Folder .. '/backups'
	}

	for i = 1, #paths do
		local str = paths[i]
		if not isfolder(str) then
			makefolder(str)
		end
	end
end

function SaveManager:RefreshConfigList()
	self:CheckFolderTree()
	local list = listfiles(self.Folder .. '/settings')

	local out = {}
	for i = 1, #list do
		local file = list[i]
		if file:sub(-5) == '.json' then
			local pos = file:find('.json', 1, true)
			local start = pos

			local char = file:sub(pos, pos)
			while char ~= '/' and char ~= '\\' and char ~= '' do
				pos = pos - 1
				char = file:sub(pos, pos)
			end

			if char == '/' or char == '\\' then
				table.insert(out, file:sub(pos + 1, start - 1))
			end
		end
	end
	
	table.sort(out, function(a, b)
		local metaA = self:GetConfigMetadata(a)
		local metaB = self:GetConfigMetadata(b)
		return (metaA.lastModified or 0) > (metaB.lastModified or 0)
	end)
	
	return out
end

function SaveManager:SetLibrary(library)
	self.Library = library
end

function SaveManager:LoadAutoloadConfig()
	self:CheckFolderTree()
	
	if isfile(self.Folder .. '/settings/autoload.txt') then
		local name = readfile(self.Folder .. '/settings/autoload.txt')

		local success, err = self:Load(name)
		if not success then
			return self.Library:Notify('Failed to load autoload config: ' .. err)
		end

		self.Library:Notify(string.format('Auto loaded config %q', name))
	end
end

function SaveManager:BuildConfigSection(tab)
	assert(self.Library, 'Must set SaveManager.Library')

	local section = tab:AddRightGroupbox('Configuration')

	section:AddInput('SaveManager_ConfigName', { Text = 'Config name' })
	section:AddInput('SaveManager_ConfigDescription', { Text = 'Description (optional)' })
	
	section:AddButton('Create config', function()
		local name = getgenv().Linoria.Options.SaveManager_ConfigName.Value
		local description = getgenv().Linoria.Options.SaveManager_ConfigDescription.Value

		if name:gsub(' ', '') == '' then 
			return self.Library:Notify('Invalid config name (empty)', 2)
		end

		local success, err = self:Save(name, description)
		if not success then
			return self.Library:Notify('Failed to create config: ' .. err)
		end

		self.Library:Notify(string.format('Created config %q', name))

		getgenv().Linoria.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
		getgenv().Linoria.Options.SaveManager_ConfigList:SetValue(nil)
	end)

	section:AddDivider()

	section:AddDropdown('SaveManager_ConfigList', { Text = 'Config list', Values = self:RefreshConfigList(), AllowNull = true })
	
	section:AddButton('Load config', function()
		local name = getgenv().Linoria.Options.SaveManager_ConfigList.Value

		local success, err = self:Load(name)
		if not success then
			return self.Library:Notify('Failed to load config: ' .. err)
		end

		self.Library:Notify(string.format('Loaded config %q', name))
	end)
	
	section:AddButton('Validate config', function()
		local name = getgenv().Linoria.Options.SaveManager_ConfigList.Value
		if not name then
			return self.Library:Notify('No config selected')
		end

		local success, message = self:ValidateConfig(name)
		if success then
			self.Library:Notify('Config is valid: ' .. message)
		else
			self.Library:Notify('Config invalid: ' .. message, 4)
		end
	end)
	
	section:AddButton('Overwrite config', function()
		local name = getgenv().Linoria.Options.SaveManager_ConfigList.Value
		local description = getgenv().Linoria.Options.SaveManager_ConfigDescription.Value

		local success, err = self:Save(name, description)
		if not success then
			return self.Library:Notify('Failed to overwrite config: ' .. err)
		end

		self.Library:Notify(string.format('Overwrote config %q', name))
	end)
	
	section:AddButton('Duplicate config', function()
		local name = getgenv().Linoria.Options.SaveManager_ConfigList.Value
		local newName = getgenv().Linoria.Options.SaveManager_ConfigName.Value
		
		if not name then
			return self.Library:Notify('No config selected')
		end
		
		if newName:gsub(' ', '') == '' then
			newName = name .. '_copy'
		end

		local success, err = self:Duplicate(name, newName)
		if not success then
			return self.Library:Notify('Failed to duplicate: ' .. err)
		end

		self.Library:Notify(string.format('Duplicated %q to %q', name, newName))
		getgenv().Linoria.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
	end)
	
	section:AddButton('Delete config', function()
		local name = getgenv().Linoria.Options.SaveManager_ConfigList.Value

		local success, err = self:Delete(name)
		if not success then
			return self.Library:Notify('Failed to delete config: ' .. err)
		end

		self.Library:Notify(string.format('Deleted config %q', name))
		getgenv().Linoria.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
		getgenv().Linoria.Options.SaveManager_ConfigList:SetValue(nil)
	end)

	section:AddDivider()
	
	section:AddButton('Export config', function()
		local name = getgenv().Linoria.Options.SaveManager_ConfigList.Value
		if not name then
			return self.Library:Notify('No config selected')
		end

		local success, message = self:Export(name)
		if success then
			self.Library:Notify(message)
		else
			self.Library:Notify('Export failed: ' .. message, 4)
		end
	end)
	
	section:AddButton('Import from clipboard', function()
		if not getclipboard then
			return self.Library:Notify('Clipboard not available', 4)
		end
		
		local clipboardData = getclipboard()
		if not clipboardData or clipboardData == '' then
			return self.Library:Notify('Clipboard is empty', 4)
		end
		
		local newName = getgenv().Linoria.Options.SaveManager_ConfigName.Value
		if newName:gsub(' ', '') == '' then
			newName = 'imported_' .. os.time()
		end

		local success, err = self:Import(clipboardData, newName)
		if not success then
			return self.Library:Notify('Import failed: ' .. err, 4)
		end

		self.Library:Notify(string.format('Imported config as %q', newName))
		getgenv().Linoria.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
	end)

	section:AddDivider()

	section:AddButton('Refresh list', function()
		getgenv().Linoria.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
		getgenv().Linoria.Options.SaveManager_ConfigList:SetValue(nil)
	end)

	section:AddButton('Set as autoload', function()
		local name = getgenv().Linoria.Options.SaveManager_ConfigList.Value
		writefile(self.Folder .. '/settings/autoload.txt', name)
		SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
		self.Library:Notify(string.format('Set %q to auto load', name))
	end)
	
	section:AddButton('Reset autoload', function()
		local success = pcall(delfile, self.Folder .. '/settings/autoload.txt')
		if not success then 
			return self.Library:Notify('Failed to reset autoload: delete file error')
		end
			
		self.Library:Notify('Set autoload to none')
		SaveManager.AutoloadLabel:SetText('Current autoload config: none')
	end)

	SaveManager.AutoloadLabel = section:AddLabel('Current autoload config: none', true)

	if isfile(self.Folder .. '/settings/autoload.txt') then
		local name = readfile(self.Folder .. '/settings/autoload.txt')
		SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
	end

	local section = tab:AddRightGroupbox('Advanced')
	
	section:AddButton('View history', function()
		local history = self:GetHistory()
		if #history == 0 then
			return self.Library:Notify('No history available')
		end
		
		local historyText = {}
		for i = 1, math.min(10, #history) do
			local entry = history[i]
			table.insert(historyText, string.format('[%s] %s: %s', 
				os.date('%H:%M:%S', entry.timestamp),
				entry.action,
				entry.details
			))
		end
		
		if setclipboard then
			setclipboard(table.concat(historyText, '\n'))
			self.Library:Notify('History copied to clipboard')
		else
			self.Library:Notify('Recent: ' .. historyText[1])
		end
	end)
	
	section:AddButton('Clear history', function()
		self.ConfigHistory = {}
		self.Library:Notify('History cleared')
	end)
	
	section:AddButton('Clean backups', function()
		local cleaned = 0
		local backupFolder = self.Folder .. '/backups'
		
		if isfolder(backupFolder) then
			local configNames = {}
			for _, file in pairs(listfiles(self.Folder .. '/settings')) do
				if file:sub(-5) == '.json' then
					local name = file:match("([^/\\]+)%.json$")
					configNames[name] = true
				end
			end
			
			for _, file in pairs(listfiles(backupFolder)) do
				if file:sub(-5) == '.json' then
					local originalName = file:match("([^/\\]+)_backup_"):gsub(backupFolder .. '/', '')
					if not configNames[originalName] then
						delfile(file)
						local metaFile = file:gsub('.json', '.meta')
						if isfile(metaFile) then
							delfile(metaFile)
						end
						cleaned = cleaned + 1
					end
				end
			end
		end
		
		self.Library:Notify(string.format('Cleaned %d orphaned backups', cleaned))
	end)

	SaveManager:SetIgnoreIndexes({ 
		'SaveManager_ConfigList', 
		'SaveManager_ConfigName', 
		'SaveManager_ConfigDescription'
	})
end

SaveManager:BuildFolderTree()
return SaveManager
