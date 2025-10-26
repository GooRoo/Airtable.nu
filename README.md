<!--
SPDX-FileCopyrightText: © Serhii “GooRoo” Olendarenko
SPDX-FileContributor: Serhii Olendarenko <sergey.olendarenko@gmail.com>
SPDX-License-Identifier: BSD-3-Clause
-->

# Airtable.nu

This module allows to work with data stored in [Airtable](https://airtable.com/) via Web API.

## Installation

```nushell
> nupm install --git git@github.com:GooRoo/Airtable.nu.git
> use airtable
```

## Authorization

First, You need to create a [Personal Access Token here](https://airtable.com/create/tokens).

To log in, use:
```nushell
> airtable login 'your-PAT'
```
This will store your auth information **for the current session.**

Personally, I use it together with 1Password CLI like this:
```nushell
> op read "op://Vault/Airtable/API tokens/my-pat" | airtable login
```

## Usage

> [!TIP]
> In all commands, entity **names** and their corresponding **IDs** (for databases, tables, fields, etc.) could be used interchangeably. The names look better but could be changed by someone (and you'll have to adapt your scripts), while IDs are uglier but unique and always stay the same.

### Getting the list of databases

> [!NOTE]
> The operation requires [`schema.bases:read`](https://airtable.com/developers/web/api/scopes#schema-bases-read) scope.

```nushell
> airtable db list
```

### Listing the tables with their schemas

> [!NOTE]
> The operation requires [`schema.bases:read`](https://airtable.com/developers/web/api/scopes#schema-bases-read) scope.

```nushell
> airtable db list | get 0.id | airtable db tables
```

### Choosing active database

If you don't want to pass the database ID manually to all commands that require it, you can store it **for the current session** like this:

```nushell
> let dbs = airtable db list
> airtable db use $dbs.0.id
```
or as a one-liner:
```nushell
> airtable db list | get 0.id | airtable db use
```

### Working with tables

#### Getting the data

> [!NOTE]
> The operation requires [`data.records:read`](https://airtable.com/developers/web/api/scopes#data-records-read) scope.

Simply call:

```nushell
> airtable table show 'your-table-id'
```

You can also pass the table ID via pipe:

```nushell
> 'your-table-id' | airtable table show
```

> [!WARNING]
> This command requires a database ID to which a table belongs. If you haven't chosen the active DB like it is shown above, you can pass it through the pipe:
> ```nushell
> > {base_id: 'your-db-id', table_id: 'your-table-id'} | airtable table show
> ```

You can also limit the fields you want to retrieve:

```nushell
> 'Clients' | airtable table show --fields [Name Country Email]
```

Additionally, you can sort the fields:

```nushell
> 'Clients' | airtable table show --sort [[field direction];[Name asc],[Birthdate desc]]
```

> [!NOTE]
> Sorting on Airtable's backend side is not the same as sorting in Nushell! Consider the following:
> ```nushell
> 'Clients' | airtable table show | take 20 | sort-by Name
> ```
> Here, you want to get information about the first 20 clients sorted by their names. However, the order, in which Airtable returns the records, is not specified. As a result, you get 20 random client records and then sort them by name.
> Instead, the correct way would be this:
> ```nushell
> 'Clients' | airtable table show -s [{field: Name, direction: asc}] | take 20
> ```
