--[[
	Varenst entry #2 

	This time writing this without headache

	This code is a server side component of simulator games pet system
	Handling stuff like Hatching, Equiping, UnEquiping, Inventory, Updating equiped pets

	The following code is a modulescript under
	ServerApplication(ServerScript)/PlayerData(ModuleScript)/PetStorage(Current module script)
]]

-----------------------------------------------------------
--------------------- TYPE DEFINITION ---------------------
-----------------------------------------------------------

--[[
	PlayerData, is a playerobject that is created in the parent module
	and is sent inside of created PetStorage component using dependency injection (advanced programming terminology scary)

	The object contains methods and data, related to player
	Data: Coins, Gems, HasGamePass
	Methods: UpdateClient(), updates the client side, when the data on the server changes

	The playerdata component is in server rather then in client, so that first it is possible to data store and second no exploits can access it.
]]

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

--// Unused sections, but that's how I ussualy structure code
--// Inspired by FastCasts developer structure, when I studied it I found it really make all of the code look clean
-----------------------------------------------------------
------------------------ UTILITIES ------------------------
-----------------------------------------------------------

-----------------------------------------------------------
------------------------ DEBUGGING ------------------------
-----------------------------------------------------------

-----------------------------------------------------------
------------------------ CORE CODE ------------------------
-----------------------------------------------------------

--// this returns an array with the targetcframes of the pets equipeed
--// I basically get player lookvector and rightvector
--// that allows me to access any point on the xz plane
--// then using petcount I position them accordingly
--// by dividing the array amount of pets by 2
--// and looping trough pets each time getting 2 new goalcframes
--// then using n % 2 I know if the array is even
--// if it's not then I position last one right behind the player
--// to make them look forward I simply use the CFrame.lookvector(GoalPosition, GoalPosition + lookvectore * x)
--// That creates a rigidbody matrix pointing forward where the player is looking
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

--// This is where I create the petstorage
--// I couldve just created it using metatable,
--// but I feel like if the object will not be created multiple times for each player
--// it doesn't make sense
--// So I wrote creating without it, with all of the methods inside of it
--// Now 3 months later after writing this code, I would do instead a modulescript
--// named CreatePetStorage that would return a function when required instead to be more
--// into functional programming architecture
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

	--// IsUID in inventory, is a function
	--// that basically is needed whenever we are unequiping or equiping pets or removing,
	--// to see that we don't accidentally equip the same pet twice
	--// or unequip pet that is not equiped
	--// or remove and forget to unequip it
	local function IsUidInInventory(CheckingUID)
		for PetId, UIDArray in pairs(Storage.PetInventory) do
			for Index, UID in pairs(UIDArray) do
				if UID == CheckingUID then return tonumber(PetId), Index end
			end
		end
	end

	--// Simply counts how much of the storage currently is taken
	--// because the structure is not a simple array we cannot just  #Storage.PetInventory
	local function CurrentStorageSpaceTaken()
		local StorageCount = 0
		
		for PetId, UIDArray in pairs(Storage.PetInventory) do
			StorageCount += #UIDArray
		end
		
		return StorageCount
	end

	--// Generates a Unique Indentifier
	--// Can be optimized using Random.new()
	--// But this gets the job done
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

	--// table.sort kind of relative order of equal elements algorithm
	--// to find the best multiplayers for pets, that give a percentage of the best pets multiplayer
	local function FindBestInvenotryPetMultiplayer()
		local BestInventoryMultiplayer = 1
		
		for PetId, UIDArray in pairs(Storage.PetInventory) do
			BestInventoryMultiplayer = PetData[tonumber(PetId)].Multiplier > BestInventoryMultiplayer and PetData[tonumber(PetId)].Multiplier or BestInventoryMultiplayer
		end
		
		return BestInventoryMultiplayer
	end
	
	--// checks if current space is taken by simply comparing Storage.MaxEquipedPets == #Storage.PetInventory
	function Storage.CurrentStorageSpaceTaken()
		return CurrentStorageSpaceTaken()
	end

	--// Simple get method, to retrive all of the important Storage data
	function Storage.GetData()
		return {
			PetInventory = Storage.PetInventory,
			CurrentEquipedPets = Storage.CurrentEquipedPets,
			MaxInventoryPets = Storage.MaxInventoryPets,
			MaxEquipedPets = Storage.MaxEquipedPets,
		}
	end
	
	--// PetData is a configuration that has the pet id and the multiplier, 
	--// so this returns the sum of all equipeed pet multiplayers
	unction Storage.GetCurrentMultiplayer()
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

	--// Update method for the pets that are equiped
	--// MovementTransform is a cframe that does the animation of the pet going up and down
	--// If the player is not moving it goes simply up and down
	--// if player is moving it rotates left and right
	--// As for why it's not client sided is simply because I was a bit lazy on the implementation
	--// and got to a point the reimplementing this would require quite a bit of refactoring
	--// but using network ownership is defo one of the ways to improve it 
	--// aswell as keep track of which pets are equiped and which aren't
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
	
	--// Equips pets
	--// code itself doesn't explain it really well, but the UID object can be 
	--// a single UID number and an array/table, if this is an array it will go trough each UID inside the array and equip them
	--// if it's not it will do it one time
	--// Whenever a pet is equiped it first checks if the pet isn't already equiped 
	--// if there are way to many pets it unequips the bottom on the stack
	--// then it creates pets model and updates client
	function Storage.EquipPets(UID)
		if type(UID) == "table" then
			for Index, RealUid in pairs(UID) do
				Storage.EquipPets(RealUid)
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
	
	--//Does the opposite of the equip pets
	--// logic is the same instead of this one finding the uid inside equiped pets and unequiping it
	--// with that destroying the model
	--// if callback is true it doesn't update the client for instances where multiple UIDs are sent
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

	--// Finds the bottom of the stack of equipped pets and destroys it + removes from current pets equipped
	function Storage.UnequipFirstPet()
		CurrentPetModels[Storage.CurrentEquipedPets[1]]:Destroy()
		CurrentPetModels[Storage.CurrentEquipedPets[1]] = nil
		
		table.remove(Storage.CurrentEquipedPets, 1)
	end
	
	--// Adding the pet to the player
	--// the strcture of Storage.PetInventory is
	--[[
		Storage.PetInventory = {
		   [PetId] = Amount,
		}
	]]
	
	--// With petid you can find the pet related data in configurations 
	--// the amount shows how many of the pet your getting
	--// and NoCallback is basically for the instances where I chaing function calls 
	--// and don't want to get stack overflow error
	--// (I think it was called that when you send to many RemoteEvent requests, but I might be wrong here)
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
	--// All of the concepts I explained already so nothing intresting
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
	--// basically to get a golden pet you need to sacrifice your pets
	--// sacrifice 1 you get 20% of getting it
	--// 3 = 60%; 5 = 100%
	--// math.random gets a random number between 1 and 5
	--// if the number of pets sacrificed is higher or equal to the randomnumber
	--// you get the golden pet
	function Storage.GetGoldenPet(CurrentSamplePetId, UidArray)
		if #UidArray == 0 then return end
		
		local x = math.random(1, 5)
		
		Storage.RemovePet(UidArray)
		
		if x > #UidArray then return end
		
		Storage.AddPet(PetIdGoldenMap[tonumber(CurrentSamplePetId)], 1)
	end
	
	--// Hatching logic with all of the multiplayers on luck
	--// firstoff checs if you have enough money and inventory storage
	--// if you don't have it fires a remote that notifies the player of it
	--// then using quite long calculation by multiplaying with lucj calculates your random number
	--// then using eggdata, which is a configuration of an egg
	--[[
		EggData[EggId].Data = {
		[Chance] = PetId
		}
	]]
	--// you compare your random chosen number to it
	--// if it's smaller then the next on, you get the current selcted
	--// NoPetIDs, basically player can choose which pets he doesn't want in his inventory from the egg
	--// if the hatched petid is in there, it just doesn't run further and player gets nothing
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
	--// simple clear function
	function Storage.Remove()
		for Index, Model in pairs(CurrentPetModels) do
			Model:Destroy()
		end
	end
	
	return Storage
end

return PetStorage
