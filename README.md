# phobos-database-sql

The `phobos.database.sql` library provides standardized, ADO.NET-style object-oriented access to any SQL data source that provides a compliant ODBC driver. It is built on top of the D-native `odbc-d` wrapper and provides strong typing, interpolated strings for parameterized queries, and integrated `Decimal128` support for monetary and high-precision numeric types.

## Features

* **ADO.NET-like API:** Familiar classes like `SqlConnection`, `SqlCommand`, `SqlDataReader`, and `SqlTransaction`.
* **Safe Parameterization:** Uses D's interpolated strings (`i"..."`) to automatically prepare and bind query parameters, eliminating SQL injection vulnerabilities.
* **Row Caching:** Data readers buffer the current row, allowing columns to be read multiple times and in any order.
* **High-Precision Decimals:** Native `Decimal128` support for SQL `DECIMAL`, `NUMERIC`, and `MONEY` types via `phobos-sys-exttypes`, preventing floating-point rounding errors.
* **Exception-based Error Handling:** ODBC diagnostic records are automatically rolled up into comprehensive `ODBCException` messages.

## Installation

Add the library to your project using DUB:

```console
dub add phobos-database-sql
```

Or add it directly to your `dub.sdl`:
```sdl
dependency "phobos-database-sql" version="~>1.0.0"
```

## Examples

### Connecting to a Database

```d
import phobos.database.sql;
import std.stdio;

void main() {
    string connStr = "DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;DATABASE=master;UID=sa;PWD=SecretPassword;";
    auto conn = new SqlConnection(connStr);
    
    // Automatically close the connection when going out of scope
    conn.open();
    scope(exit) conn.close();

    writeln("Connected to: ", conn.serverVersion);
}
```

### Executing Non-Queries (with Interpolated Strings)

```d
import phobos.database.sql;

void insertUser(SqlConnection conn, int id, string name, double score) {
    // Variables within $(...) are automatically bound as secure ODBC parameters!
    auto cmd = new SqlCommand(conn, i"INSERT INTO Users (id, name, score) VALUES ($(id), $(name), $(score))");
    scope(exit) cmd.dispose();
    
    int rowsAffected = cmd.executeNonQuery();
}
```

### Reading Data

```d
import phobos.database.sql;
import std.stdio;

void printUsers(SqlConnection conn) {
    auto cmd = new SqlCommand(conn, i"SELECT id, name, balance FROM Users ORDER BY id");
    scope(exit) cmd.dispose();
    
    auto reader = cmd.executeDataReader();
    scope(exit) reader.close();
    
    while (reader.read()) {
        int id = reader.getInt(0);
        string name = reader.isNull(1) ? "Unknown" : reader.getString(1);
        
        // High-precision decimal support
        auto balance = reader.getDecimal(2);
        
        writeln("ID: ", id, " Name: ", name, " Balance: ", balance.toString());
    }
}
```

### Transactions

```d
import phobos.database.sql;

void runInTransaction(SqlConnection conn) {
    auto txn = conn.beginTransaction(IsolationLevel.serializable);
    
    try {
        auto cmd = new SqlCommand(conn, i"UPDATE Accounts SET balance = balance - 100 WHERE id = 1");
        cmd.executeNonQuery();
        cmd.dispose();
        
        txn.commit(); // Only commits if no exceptions were thrown
    } catch (Exception e) {
        txn.rollback();
        throw e;
    }
}
```

## Contributing

Contributions to `phobos-database-sql` are welcome! Please submit patches and features via Pull Requests.

**Important LLM Guideline:** If you use a Large Language Model (such as GitHub Copilot, ChatGPT, Claude, etc.) to generate or assist heavily with your contribution, **you must include the exact prompt(s) you used to generate the code in the `PROMPTS.txt` file at the root of the repository.**

## License

This project is licensed under the Boost Software License 1.0. See the `LICENSE` file for details.
