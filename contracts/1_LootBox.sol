pragma solidity >=0.8.2 <0.9.0;

contract LootBoxGame {
    // ----------- STRUCTS -----------
    struct Item {
        string name;
        uint256 basePrice;
        bool inUse; 
    }

    struct WeightedItem {
        uint256 itemId;
        uint256 weight; 
    }

    struct LootBox {
        string name;
        uint256 price; 
        uint256 totalWeight; 
        bool exists;
    }

    address public admin;

    Item[] public allItems; 
    mapping(uint256 => bool) public deletedItems; 

    LootBox[] public allLootBoxes;
    mapping(uint256 => WeightedItem[]) public lootBoxItems;

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    // ----------- EVENTS -----------
    event ItemAdded(uint256 indexed itemId, string name, uint256 basePrice);
    event ItemDeleted(uint256 indexed itemId, string name);

    event LootBoxCreated(uint256 indexed lootBoxId, string name, uint256 price);
    event LootBoxDeleted(uint256 indexed lootBoxId, string name);

    event LootBoxPurchased(
        address indexed buyer,
        uint256 indexed lootBoxId,
        string lootBoxName,
        uint256 itemId,
        string itemName
    );

    // ----------- CONSTRUCTOR -----------
    constructor() {
        admin = msg.sender;
    }

    // ========== ADMIN FUNCTIONS ==========

    /**
     * @notice Add a new item to the global item list.
     * @param _name Name of the item.
     * @param _basePrice Some base price or reference price (optional usage).
     * @return itemId The index of the newly created item in `allItems`.
     */
    function addItem(string calldata _name, uint256 _basePrice)
        external
        onlyAdmin
        returns (uint256)
    {
        allItems.push(Item({name: _name, basePrice: _basePrice, inUse: false}));

        uint256 itemId = allItems.length - 1;
        emit ItemAdded(itemId, _name, _basePrice);

        return itemId;
    }

    /**
     * @notice Admin can delete an item if it is not in use by any lootbox.
     *         We'll mark it as "deleted" in `deletedItems` mapping and remove
     *         it from availability. (We won't actually remove from array to keep it simple.)
     * @param _itemId The ID of the item to delete.
     */
    function deleteItem(uint256 _itemId) external onlyAdmin {
        require(_itemId < allItems.length, "Invalid itemId");
        require(!allItems[_itemId].inUse, "Item is used in a lootbox");
        require(!deletedItems[_itemId], "Item already deleted");

        deletedItems[_itemId] = true;
        emit ItemDeleted(_itemId, allItems[_itemId].name);
    }

    /**
     * @notice Create a new lootbox with an array of weighted items.
     *         Example usage:
     *         WeightedItem[] => (itemId=1, weight=50), (itemId=2, weight=30), ...
     *         totalWeight = 80 in that case.
     * @param _name  Name of this lootbox (for display).
     * @param _price Price in Wei to buy this lootbox.
     * @param _items Array of WeightedItem (itemId, weight).
     * @return lootBoxId The index of the newly created lootbox in `allLootBoxes`.
     */
    function createLootBox(
        string calldata _name,
        uint256 _price,
        WeightedItem[] calldata _items
    ) external onlyAdmin returns (uint256) {
        require(_items.length > 0, "No items provided");

        // Calculate total weight and validate items
        uint256 totalWeightTemp = 0;

        for (uint256 i = 0; i < _items.length; i++) {
            // Validate item
            require(
                _items[i].itemId < allItems.length,
                "Invalid itemId in WeightedItem"
            );
            require(!deletedItems[_items[i].itemId], "Item is deleted");
            require(_items[i].weight > 0, "Weight must be > 0");

            // Mark that item as in use
            allItems[_items[i].itemId].inUse = true;

            totalWeightTemp += _items[i].weight;
        }

        // Create a new lootbox without items array inside
        allLootBoxes.push(
            LootBox({
                name: _name,
                price: _price,
                totalWeight: totalWeightTemp,
                exists: true
            })
        );

        uint256 newLootBoxId = allLootBoxes.length - 1;

        // Add items to the separate mapping
        for (uint256 i = 0; i < _items.length; i++) {
            lootBoxItems[newLootBoxId].push(
                WeightedItem({
                    itemId: _items[i].itemId,
                    weight: _items[i].weight
                })
            );
        }

        emit LootBoxCreated(newLootBoxId, _name, _price);
        return newLootBoxId;
    }

    /**
     * @notice Delete a lootbox by ID. This sets `exists = false` and
     *         makes items available for other lootboxes or deletion if needed.
     * @param _lootBoxId The ID of the lootbox to delete.
     */
    function deleteLootBox(uint256 _lootBoxId) external onlyAdmin {
        require(_lootBoxId < allLootBoxes.length, "Invalid lootBoxId");
        LootBox storage lb = allLootBoxes[_lootBoxId];
        require(lb.exists, "LootBox already deleted");

        // Mark items in that lootbox as not in use
        WeightedItem[] storage items = lootBoxItems[_lootBoxId];
        for (uint256 i = 0; i < items.length; i++) {
            uint256 itemId = items[i].itemId;
            // Make sure to set inUse = false only if it's not used by another lootbox
            // (In a more advanced contract, you'd track usage count or references.)
            // For simplicity, let's just set to false. But be aware if items are used in multiple boxes,
            // you'd need a reference count to truly handle it.
            allItems[itemId].inUse = false;
        }

        lb.exists = false;

        emit LootBoxDeleted(_lootBoxId, lb.name);
    }

    // ========== PLAYER FUNCTIONS ==========

    /**
     * @notice Return the number of lootboxes in `allLootBoxes` array.
     *         Some might be deleted, so front-end can filter those out by `exists` flag.
     */
    function getAllLootBoxesCount() external view returns (uint256) {
        return allLootBoxes.length;
    }

    /**
     * @notice Get info about a lootbox by ID.
     *         This helps front-end list all lootboxes with their name, price, etc.
     */
    function getLootBoxInfo(uint256 _lootBoxId)
        external
        view
        returns (
            string memory name,
            uint256 price,
            bool isActive,
            uint256 totalWeight,
            uint256 itemsCount
        )
    {
        require(_lootBoxId < allLootBoxes.length, "Invalid lootBoxId");
        LootBox storage lb = allLootBoxes[_lootBoxId];
        uint256 itemsCount = lootBoxItems[_lootBoxId].length;

        return (lb.name, lb.price, lb.exists, lb.totalWeight, itemsCount);
    }

    /**
     * @notice Get items for a specific lootbox by ID.
     * @param _lootBoxId The ID of the lootbox.
     * @return Array of WeightedItem structs for this lootbox.
     */
    function getLootBoxItems(uint256 _lootBoxId) 
        external 
        view 
        returns (WeightedItem[] memory) 
    {
        require(_lootBoxId < allLootBoxes.length, "Invalid lootBoxId");
        return lootBoxItems[_lootBoxId];
    }

    /**
     * @notice Buy a lootbox using Ether (msg.value must be >= lootbox price).
     *         Randomly select an item based on the weight distribution.
     * @param _lootBoxId The ID of the lootbox to purchase.
     */
    function buyLootBox(uint256 _lootBoxId) external payable {
        require(_lootBoxId < allLootBoxes.length, "Invalid lootBoxId");
        LootBox storage lb = allLootBoxes[_lootBoxId];
        require(lb.exists, "LootBox does not exist");

        // Payment check
        require(msg.value >= lb.price, "Not enough Ether to buy this lootbox");

        WeightedItem[] storage items = lootBoxItems[_lootBoxId];
        require(items.length > 0, "No items in lootbox");

        // -- Randomness (not secure!) --
        // This is a naive approach for demonstration
        uint256 rand = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    msg.sender,
                    block.timestamp
                )
            )
        ) % lb.totalWeight;

        // Find which item index is picked
        uint256 cumulative = 0;
        uint256 selectedItemIndex = 0;

        for (uint256 i = 0; i < items.length; i++) {
            cumulative += items[i].weight;
            if (rand < cumulative) {
                selectedItemIndex = i;
                break;
            }
        }

        // The WeightedItem we picked
        WeightedItem storage wItem = items[selectedItemIndex];
        Item storage itemInfo = allItems[wItem.itemId];

        // Return item name in an event
        emit LootBoxPurchased(
            msg.sender,
            _lootBoxId,
            lb.name,
            wItem.itemId,
            itemInfo.name
        );
    }

    // ========== ADMIN WITHDRAWAL (OPTIONAL) ==========

    /**
     * @notice Admin can withdraw Ether from the contract balance.
     */
    function adminWithdraw(address payable _to, uint256 _amount)
        external
        onlyAdmin
    {
        require(
            _amount <= address(this).balance,
            "Insufficient contract balance"
        );
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "Withdraw transfer failed");
    }
}