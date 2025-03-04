-----------------------------------------------------------
--------------------- TYPE DEFINITION ---------------------
-----------------------------------------------------------

type PlayerData = {
	UpdateClient : () -> (),
}

-----------------------------------------------------------
-------------------- MODULE DEFINITION --------------------
-----------------------------------------------------------

local PetStorage = {}

-----------------------------------------------------------
----------------------- STATIC DATA -----------------------
-----------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage.RemoteEvent

local ReceiveNotification = RemoteEvents.ReceiveNotification

local PetData = require(script.PetData)
local EggData = require(script.EggData)

local StepDelta = 4

local PetIdGoldenMap = {
	[1] = 3,
	[2] = 4,
}

-----------------------------------------------------------
------------------------ UTILITIES ------------------------
-----------------------------------------------------------

-----------------------------------------------------------
------------------------ DEBUGGING ------------------------
-----------------------------------------------------------

-----------------------------------------------------------
------------------------ CORE CODE ------------------------
-----------------------------------------------------------

local function GetPetCFrames(PetIds, PlayerCFrame : CFrame, RayParams)
	local CFrames = {}
	
	local PlayerLookVector = PlayerCFrame.LookVector
	local PlayerRightVector = PlayerCFrame.RightVector

	local n = #PetIds
	
	if n == 1 then --// If there is only 1 pet, place it right behind the player by simply subtracting the lookvector from player position
		local GoalPosition = PlayerCFrame.Position - PlayerLookVector * StepDelta
		
		local Results = workspace:Raycast(GoalPosition + Vector3.yAxis * 7, -Vector3.yAxis * 30, RayParams)
		
		if not Results then
			return {CFrame.lookAt(GoalPosition, GoalPosition + PlayerRightVector * 8)}
		else
			return {CFrame.lookAt(Results.Position, Results.Position - PlayerRightVector * 8)}
		end
	end

	for i = 1, math.floor(n/2) do --// n/2, if there are 3 pets it would be 1.5 by flooring we get 1 meaning we get 2 positions instead of 4
		local GoalPosition1 = PlayerCFrame.Position + (-PlayerLookVector * StepDelta * i) + (PlayerRightVector * 4)
		local GoalPosition2 = PlayerCFrame.Position + (-PlayerLookVector * StepDelta * i) + (-PlayerRightVector * 4)

		--// Raycasts to understand if anything is below the pets, if there is then the pet will stand on them
		local Results1 = workspace:Raycast(GoalPosition1 + Vector3.yAxis * 7, -Vector3.yAxis * 30, RayParams)
		local Results2 = workspace:Raycast(GoalPosition2 + Vector3.yAxis * 7, -Vector3.yAxis * 30, RayParams)
		
		local CFrame1 = Results1 and
			CFrame.lookAt(Results1.Position, (Results1.Position - PlayerRightVector * 16))
			or 	CFrame.lookAt(GoalPosition1, (GoalPosition1 - PlayerRightVector * 16))
		
		local CFrame2 = Results2 and
			CFrame.lookAt(Results2.Position, (Results2.Position - PlayerRightVector * 16))
			or 	CFrame.lookAt(GoalPosition2, (GoalPosition2 - PlayerRightVector * 16))
		
		table.insert(CFrames, CFrame1)
		table.insert(CFrames, CFrame2)
	end

	local IsEven = n % 2 == 0
	
	--// If it's not even then it applies the same logic as in the first if statement
	if not IsEven then
		local MaxPetsRow = math.ceil(n/2)

		local GoalPosition = PlayerCFrame.Position - PlayerLookVector * StepDelta * MaxPetsRow
		
		local Results = workspace:Raycast(GoalPosition + Vector3.yAxis * 7, -Vector3.yAxis * 30, RayParams)

		if not Results then
			table.insert(CFrames, CFrame.lookAt(GoalPosition, GoalPosition + PlayerRightVector * 16))
		else
			table.insert(CFrames, CFrame.lookAt(Results.Position, Results.Position - PlayerRightVector * 16))
		end
	end
	
	return CFrames
end

-----------------------------------------------------------
------------------------- EXPORTS -------------------------
-----------------------------------------------------------

--//PlayerData, is an playerobject that has data inside of it
--//for example, 'Has2xdamage gampass', 'cash', and more
--// Also no metatables simply, because I think this looks more intuitive based on my experience with Rust programming language
function PetStorage.new(Player : Player, PlayerData : PlayerData)
	local Storage = {
		PetInventory = {},
		CurrentEquipedPets = {},
		MaxInventoryPets = 75,
		MaxEquipedPets = 4,
	}
	
	local StartTime = nil
	local IsPlayerMoving = false
	local CurrentPetModels = {}
	local UsedUIDs = {}
	
	local PetParams = RaycastParams.new()
	PetParams.FilterType = Enum.RaycastFilterType.Exclude
	
	--// Functions that are used only by this object are local, to not overwhelm whoever creates it
	local function IsUidInInventory(CheckingUID)
		for PetId, UIDArray in pairs(Storage.PetInventory) do
			for Index, UID in pairs(UIDArray) do
				if UID == CheckingUID then return tonumber(PetId), Index end
			end
		end
	end
	
	local function CurrentStorageSpaceTaken()
		local StorageCount = 0
		
		for PetId, UIDArray in pairs(Storage.PetInventory) do
			StorageCount += #UIDArray
		end
		
		return StorageCount
	end
	
	local function GenerateUID()
		local NewUid = math.random(1, 100000)
		
		if UsedUIDs[NewUid] then
			UsedUIDs[NewUid] = true
			
			return GenerateUID()
		else
			UsedUIDs[NewUid] = true
			
			return NewUid
		end
	end
	
	local function FindBestInvenotryPetMultiplayer()
		local BestInventoryMultiplayer = 1
		
		for PetId, UIDArray in pairs(Storage.PetInventory) do
			BestInventoryMultiplayer = PetData[tonumber(PetId)].Multiplier > BestInventoryMultiplayer and PetData[tonumber(PetId)].Multiplier or BestInventoryMultiplayer
		end
		
		return BestInventoryMultiplayer
	end
	
	--// checks if current space is taken by simply comparing current pet amounts to max pet amounts
	function Storage.CurrentStorageSpaceTaken()
		return CurrentStorageSpaceTaken()
	end
	
	function Storage.GetData()
		return {
			PetInventory = Storage.PetInventory,
			CurrentEquipedPets = Storage.CurrentEquipedPets,
			MaxInventoryPets = Storage.MaxInventoryPets,
			MaxEquipedPets = Storage.MaxEquipedPets,
		}
	end
	
	--// PetData is a configuration that has the pet id and the multiplier, so this returns the sum of all equipeed pet multiplayers
	function Storage.GetCurrentMultiplayer()
		local Multiplayer = 1
		
		for Index, UID in pairs(Storage.CurrentEquipedPets) do
			local PetId = IsUidInInventory(UID)
			
			if PetData[tonumber(PetId)].BestPetPercentage then
				Multiplayer += (FindBestInvenotryPetMultiplayer() * PetData[tonumber(PetId)].BestPetPercentage)
				
				continue
			end
			
			Multiplayer += PetData[tonumber(PetId)].Multiplier
		end
		
		return Multiplayer
	end
	
	function Storage.Update(deltaTime)
		local Character = Player.Character
		
		if not Character then return end
		
		local HumanoidRootPart : BasePart = Character:FindFirstChild("HumanoidRootPart")
		local Humanoid : Humanoid = Character:FindFirstChild("Humanoid")
		
		if not HumanoidRootPart then return end
		
		local CurrentPetIds = {}
		
		for Index, UID in pairs(Storage.CurrentEquipedPets) do
			local PetId = IsUidInInventory(UID)
			
			table.insert(CurrentPetIds, PetId)
		end
		
		local CFramesFromPoint = GetPetCFrames(CurrentPetIds, HumanoidRootPart.CFrame, PetParams)

		if Humanoid.MoveDirection.Magnitude == 0 then
			IsPlayerMoving = false
		elseif Humanoid.MoveDirection.Magnitude ~= 0 and not IsPlayerMoving then
			IsPlayerMoving = true
			StartTime = tick()
		end
		
		--// Cool up and down + right and left animation
		local MovementTransform = IsPlayerMoving and CFrame.Angles(math.rad(8 * math.cos((tick() - StartTime) * 5)), 0, 0) or CFrame.Angles(0, 0, 0)

		local CFrameIndex = 1
		
		for Uid, Model : Model in pairs(CurrentPetModels) do
			Model.PrimaryPart.CFrame = Model.PrimaryPart.CFrame:Lerp(CFramesFromPoint[CFrameIndex] * CFrame.new(0, 0.2 * math.sin(tick()), 0) * MovementTransform, 0.1)
			Model.PrimaryPart.Transparency = 1
			Model.PrimaryPart.CanCollide = false
			Model.PrimaryPart.CanQuery = false
			Model.PrimaryPart.CanTouch = false
		
			CFrameIndex += 1
		end
	end
	
	--// Equips the pet
	function Storage.EquipPets(UID)
		if type(UID) == "table" then
			for Index, RealUid in pairs(UID) do
				Storage.EquipPets(RealUid, true)
			end

			PlayerData.UpdateClient()
			
			return
		end
		
		local PetId = IsUidInInventory(UID)
		
		if not PetId then return end
		if table.find(Storage.CurrentEquipedPets, UID) then return end
		if #Storage.CurrentEquipedPets + 1 > Storage.MaxEquipedPets then
			Storage.UnequipFirstPet()
		end
		
		local ClonedModel = PetData[PetId].Model:Clone()
		ClonedModel.PrimaryPart.Transparency = 1
		ClonedModel.PrimaryPart.CanCollide = false
		ClonedModel.PrimaryPart.CanQuery = false
		ClonedModel.PrimaryPart.CanTouch = false
		ClonedModel.Parent = workspace.CreatedPetsStorage
		
		table.insert(PetParams.FilterDescendantsInstances, ClonedModel)
		
		CurrentPetModels[UID] = ClonedModel
		
		table.insert(Storage.CurrentEquipedPets, UID)
		
		PlayerData.UpdateClient()
	end
	
	--//Unequips the pet
	function Storage.UnequipPets(UID, callback)
		if type(UID) == "table" then
			for Index, RealUid in pairs(UID) do
				Storage.UnequipPets(RealUid, true)
			end
			
			PlayerData.UpdateClient()
			
			return
		end
		
		local InventoryIndex = table.find(Storage.CurrentEquipedPets, UID)
		
		if InventoryIndex then
			table.remove(Storage.CurrentEquipedPets, InventoryIndex)
			
			CurrentPetModels[UID]:Destroy()
			CurrentPetModels[UID] = nil
			
			if callback then return end
			
			PlayerData.UpdateClient()
		end
	end	
	
	function Storage.UnequipFirstPet()
		CurrentPetModels[Storage.CurrentEquipedPets[1]]:Destroy()
		CurrentPetModels[Storage.CurrentEquipedPets[1]] = nil
		
		table.remove(Storage.CurrentEquipedPets, 1)
	end
	
	--// Adds Pet to storage
	function Storage.AddPet(PetId, Amount, NoCallback)
		if CurrentStorageSpaceTaken() + Amount > Storage.MaxInventoryPets then return end
	
		if not Storage.PetInventory[tostring(PetId)] then
			Storage.PetInventory[tostring(PetId)] = {}
		end
		
		for I = 1, Amount do
			local NewUid = GenerateUID()
			
			table.insert(Storage.PetInventory[tostring(PetId)], NewUid)
		end
		
		if NoCallback then return end
		
		PlayerData.UpdateClient()
	end
	
	--// Removes Pet from storage
	function Storage.RemovePet(RemovePetIds)
		for Index, UID in pairs(RemovePetIds) do
			Storage.UnequipPets(UID, true)
			
			local PetId, Index = IsUidInInventory(UID)
			
			table.remove(Storage.PetInventory[tostring(PetId)], Index)
			
			UsedUIDs[UID] = nil
		end
		
		PlayerData.UpdateClient()
	end
	
	--// Creates a golden pet
	function Storage.GetGoldenPet(CurrentSamplePetId, UidArray)
		if #UidArray == 0 then return end
		
		local x = math.random(1, 5)
		
		Storage.RemovePet(UidArray)
		
		if x > #UidArray then return end
		
		Storage.AddPet(PetIdGoldenMap[tonumber(CurrentSamplePetId)], 1)
	end
	
	--// Hatching logic with all of the multiplayers on luck
	function Storage.HatchEgg(EggId, Amount, NoAddPetIDs)
		if CurrentStorageSpaceTaken() + Amount > Storage.MaxInventoryPets then
			ReceiveNotification:FireClient(Player, "Pet Inventory is full")
			return
		end
		
		if PlayerData.Wins - EggData[EggId].Cost < 0 then
			ReceiveNotification:FireClient(Player, "Not enough wins")
			
			return
		end
		
		PlayerData.Wins -= EggData[EggId].Cost
		
		local ReturnPetIds = {}
		
		for i = 1, Amount do
			local x = math.clamp(math.random(0, 10000)/100 * (PlayerData.Has4xLuck and 4 or 1) * (PlayerData.Has2xLuck and 2 or 1) * (PlayerData.IsUsingLuckPotion and 2 or 1), 0, 100)
			
			for Index, Data in pairs(EggData[EggId].Data) do
				if x < Data.Value then
					local IsInNoAddPet = table.find(NoAddPetIDs, Data.PetId)
					
					if not IsInNoAddPet then
						Storage.AddPet(Data.PetId, 1, true)
					end
					
					table.insert(ReturnPetIds,  Data.PetId)
					
					break
				end
			end
		end
		
		PlayerData.UpdateClient()
		
		return ReturnPetIds
	end
	
	--// when player leaves deletes pet models
	function Storage.Remove()
		for Index, Model in pairs(CurrentPetModels) do
			Model:Destroy()
		end
	end
	
	task.delay(4, function()
		PlayerData.UpdateClient()
	end)
	
	return Storage
end

return PetStorage
