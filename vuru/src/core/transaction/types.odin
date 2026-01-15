package transaction

import "core:mem"

// Transaction operation type
Transaction_Op :: enum {
	Install_Official, // Install from official Void repos
	Install_VUP,      // Install from VUP binary repo
	Build_Install,    // Build from source then install
	Remove,           // Remove package
	Upgrade,          // Upgrade package
}

// Single transaction item
Transaction_Item :: struct {
	op:          Transaction_Op,
	name:        string,
	old_version: string, // For upgrades
	new_version: string,
	repo_url:    string, // For VUP binary installs
	category:    string, // For VUP packages
	reason:      string, // "explicit" or "dependency"
}

// Complete transaction plan
Transaction :: struct {
	items:     [dynamic]Transaction_Item,
	allocator: mem.Allocator,
}

// Free all resources in a Transaction_Item
transaction_item_free :: proc(item: ^Transaction_Item, allocator: mem.Allocator) {
	if item == nil do return
	
	if len(item.name) > 0 do delete(item.name, allocator)
	if len(item.old_version) > 0 do delete(item.old_version, allocator)
	if len(item.new_version) > 0 do delete(item.new_version, allocator)
	if len(item.repo_url) > 0 do delete(item.repo_url, allocator)
	if len(item.category) > 0 do delete(item.category, allocator)
	if len(item.reason) > 0 do delete(item.reason, allocator)
}

// Free transaction and all its allocations
transaction_free :: proc(t: ^Transaction) {
	if t == nil do return
	
	for &item in t.items {
		transaction_item_free(&item, t.allocator)
	}
	delete(t.items)
}

// Create a new empty Transaction
transaction_make :: proc(allocator := context.allocator) -> Transaction {
	return Transaction {
		items     = make([dynamic]Transaction_Item, allocator),
		allocator = allocator,
	}
}

// Check if transaction is empty
transaction_is_empty :: proc(t: ^Transaction) -> bool {
	return t == nil || len(t.items) == 0
}

// Get number of items in transaction
transaction_count :: proc(t: ^Transaction) -> int {
	if t == nil do return 0
	return len(t.items)
}

// Count items by operation type
Transaction_Counts :: struct {
	install_official: int,
	install_vup:      int,
	build:            int,
	remove:           int,
	upgrade:          int,
}

transaction_count_by_op :: proc(t: ^Transaction) -> Transaction_Counts {
	counts := Transaction_Counts{}
	
	if t == nil do return counts
	
	for item in t.items {
		switch item.op {
		case .Install_Official: counts.install_official += 1
		case .Install_VUP:      counts.install_vup += 1
		case .Build_Install:    counts.build += 1
		case .Remove:           counts.remove += 1
		case .Upgrade:          counts.upgrade += 1
		}
	}
	
	return counts
}
