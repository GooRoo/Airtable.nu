# SPDX-FileCopyrightText: © Serhii “GooRoo” Olendarenko
# SPDX-FileContributor: Serhii Olendarenko <sergey.olendarenko@gmail.com>
#
# SPDX-License-Identifier: BSD-3-Clause

const settings_file = '.airtable.conf'

# Remember the auth token
#
# The token is required for all the commands that perform actual requests to Airtable API.
# It is kept only for the current session (unless you save it with `settings save`).
@example "Save the authentication token" {'my-personal-access-token' | airtable login}
export def login [
	api_key?: string,  # The API Token to save (unless you pass it via pipe).
]: [
	nothing -> nothing
	string -> nothing
] {
	let pipe_in = $in
	let key = $api_key | default $pipe_in

	try { stor delete --table-name 'airtable_auth' }
	stor create --table-name 'airtable_auth' --columns {token: str}
	stor insert --table-name 'airtable_auth' --data-record {
		token: $key
	} | ignore
}

# Delete the auth token
#
# Warning: if you used `settings save`, it could still be kept in the file. Use `settings reset` for clean it too.
export def logout [] {
	try { stor delete --table-name 'airtable_auth' }
}

# List available databases
@category api
export def "db list" []: [nothing -> table] {
	let headers = get-auth-header

	const url = 'https://api.airtable.com/v0/meta/bases'

	generate {|state = null|
		let url = match $state {
			{offset: $offset} => $'($url)&offset=($offset)'
			null => $url
			_ => { return {} }
		}

		let response = http get --headers $headers $url

		{out: $response.bases, next: $response}
	}
	| flatten
}

# Remember the database ID
#
# This database ID will be used with other commands like `table show` or `table create-items`.
# It is kept only for the current session (unless you save it with `settings save`).
@example "Activate the first database" {airtable db list | get 0.id | airtable db use}
export def "db use" [
	base_id?: string  # The database ID to remember if not comes from the pipe.
]: [
	nothing -> nothing
	string -> nothing
] {
	let pipe_in = $in
	let id = $base_id | default --empty $pipe_in

	try { stor delete --table-name 'airtable_db' }
	stor create --table-name 'airtable_db' --columns {base_id: str}
	stor insert --table-name 'airtable_db' --data-record {
		base_id: $id
	}
	| ignore
}

# List tables and their schemas
@category api
export def "db tables" [
	base_id?: string  # The ID of the database (if not comes from the pipe).
	--include (-i): list<string>@[[visibleFieldIds]]  # Additional fields to include in the views object response.
]: [
	nothing -> table
	string -> table
] {
	let pipe_in = $in
	let base_id = $base_id
		| default --empty $pipe_in
		| default (get-base-id)
		| default {
			error make {
				msg: "No database ID is provided"
				help: "Pass the ID via pipe or set it with `airtable db use`."
			}
		}

	let query = {include: ($include | default [])} | url build-query
	let headers = get-auth-header

	http get --headers $headers $'https://api.airtable.com/v0/meta/bases/($base_id)/tables?($query)'
		| get tables
}

# Get the table data
@category api
export def "table show" [
	table_id?: string  # The ID of the table to retrieve (if not comes from the pipe).
	--fields (-f): list<string>  # Only data for fields whose names are in this list will be included in the result.
	--sort (-s): table<field: string, direction: string>  # A list of sort objects that specifies how the records will be ordered. Direction key is either "asc" or "desc".
	--view (-v): string  # The name or ID of a view
	--record-metadata (-m): list<string>@[[commentCount]]  # if includes `commentCount`, adds a `commentCount` read only property on each record returned.
	--filter-formula: string   # A formula used to filter records.
	--column-ids (-i)  # Name each column as corresponding field id (by default field names are used).
]: [
	nothing -> table
	string  -> table
	record<base_id: string, table_id: string> -> table
] {
	let pipe_in = $in

	let query = $sort
		| enumerate
		| reduce --fold {} {|it, acc|
			$acc
			| merge { $'sort[($it.index)][field]': ($it.item.field) }
			| merge { $'sort[($it.index)][direction]': ($it.item.direction) }
		  }
		| merge {
			fields[]: ($fields | default [])
			view: ($view | default [])
			recordMetadata: ($record_metadata | default [])
			filterByFormula: ($filter_formula | default [])
			returnFieldsByFieldId: ($column_ids | default [])
		}
		| url build-query

	let base_id = match $pipe_in {
		{base_id: $bid} => $bid
		_ => { get-base-id }
	} | default {
		error make {
			msg: "No database ID is provided"
			help: "Pass the ID via pipe or set it with `airtable db use`."
		}
	}

	let table_id = match $pipe_in {
		{table_id: $tid} => { $table_id | default --empty $tid }
		$tid => $tid
		_ => $table_id
	} | default {
		error make {
			msg: "No table ID is provided"
			help: "Pass the ID via pipe or as first argument"
		}
	}

	let headers = get-auth-header
	let url = $'https://api.airtable.com/v0/($base_id)/($table_id)?($query)'

	generate {|state = null|
		let url = match $state {
			{offset: $offset} => $'($url)&offset=($offset)'
			null => $url
			_ => { return {} }
		}

		let response = http get $url --headers $headers

		{out: $response.records, next: $response}
	}
	| flatten
	| flatten fields
}

# Add new records to the table
@category api
export def "table create-items" [
	table_id: string  # The ID of the table to insert to.
	base_id?: string  # The ID of the database (if not set via `airtable db use`).
	--typecast        # Enable automatic data conversion from string values.
]: [
	record -> table
	table  -> table
] {
	let pipe_in = $in
	let records = if ($pipe_in | describe -d).type == 'record' {
		[$pipe_in]
	} else {
		$pipe_in
	}

	let base_id = $base_id
		| default (get-base-id)
		| default {
			error make {
				msg: "No database ID is provided"
				help: "Pass the ID via pipe or set it with `airtable db use`."
			}
		}

	let headers = get-auth-header
	let url = $'https://api.airtable.com/v0/($base_id)/($table_id)'

	$records | chunks 10 | each {|chunk|
		let fields = $chunk | reject --optional id createdTime | wrap fields
		let data = {records: $fields}
			| merge-if $typecast {typecast: true}
			| to json
		http post --headers $headers --content-type application/json $url $data
	}
	| get records
	| flatten
	| flatten fields
}

# Update or upsert records in the table
@category api
export def "table update-items" [
	table_id: string  # The ID of the table to insert to.
	base_id?: string  # The ID of the database (if not set via `airtable db use`).
	--overwrite       # If enabled, request will perform a destructive update and clear all unincluded cell values.
	--typecast        # Enable automatic data conversion from string values.
	--upsert-on: oneof<string,list<string>> # Fields to match on to decide whether an insertion or an update should be performed. This will add `newlyCreated` column to the response.
]: [
	record -> table
	table  -> table
] {
	let pipe_in = $in
	let records = if ($pipe_in | describe -d).type == 'record' {
		[$pipe_in]
	} else {
		$pipe_in
	}

	let base_id = $base_id
		| default (get-base-id)
		| default {
			error make {
				msg: "No database ID is provided"
				help: "Pass the ID via pipe or set it with `airtable db use`."
			}
		}

	let fieldsToMatch = match ($upsert_on | describe -d).type {
		'string' => [$upsert_on]
		'list' => $upsert_on
		_ => null
	}

	if ($fieldsToMatch | length) > 3  {
		error make {
			msg: "To many fields specified"
			help: "--upsert-on should contain up to 3 fields"
		}
	}

	let headers = get-auth-header
	let url = $'https://api.airtable.com/v0/($base_id)/($table_id)'

	let response = $records | chunks 10 | each {|chunk|
		let fields = $chunk | each {|row| {id: $row.id, fields: ($row | reject --optional id createdTime)}}
		let data = {records: $fields}
			| merge-if $typecast {typecast: true}
			| merge-if ($fieldsToMatch != null) {performUpsert: {fieldsToMergeOn: $fieldsToMatch}}
			| to json

		if $overwrite {
			http put --headers $headers --content-type application/json $url $data
		} else {
			http patch --headers $headers --content-type application/json $url $data
		}
	}

	let responseRecords = $response | get records | flatten

	if $fieldsToMatch != null {
		$responseRecords
			| insert newlyCreated {|row| $row.id in $response.createdRecords}
			| roll right
	} else {
		$responseRecords
	}
	| flatten fields
}

def get-base-id []: [nothing -> string] {
	try {
		stor open | query db `SELECT base_id FROM "airtable_db"`
	} catch {
		settings load
	}

	try {
		stor open | query db `SELECT base_id FROM "airtable_db"` | get 0.base_id
	}
}

def get-auth-header []: [nothing -> record<Authorization: string>] {
	try {
		stor open | query db `SELECT * FROM "airtable_auth"`
	} catch {
		settings load
	}

	let headers = try {
		{Authorization: $'Bearer (stor open | query db `SELECT token FROM "airtable_auth"` | get 0.token)'}
	} catch {
		error make {
			msg: "Forgot to log in?"
			help: " Use `airtable login`."
		}
	}

	return $headers
}

# Saves the auth token and active database into a file
#
# Warning: This is insecure since the data is saved without any encryption in the current folder.
export def "settings save" [] {
	settings reset
	stor export -f $settings_file | ignore
}

def "settings load" [] {
	if ($settings_file | path exists) {
		stor import -f $settings_file | ignore
	}
}

export def "settings reset" [] {
	if ($settings_file | path exists) { rm $settings_file }
}

def merge-if [
	condition: bool
	value: oneof<record, table>
]: [
	record -> record
	table -> table
] {
	if $condition { $in | merge $value } else { $in }
}
