module phobos.database.sql.reader;

import phobos.database.sql.command;
import etc.c.odbc.odbc64;
import std.datetime;
import std.exception;
import std.variant;
import std.uuid;

/// Base class for SQL data readers.
abstract class DbDataReader
{
    /// Advances the reader to the next record.
    abstract bool read();

    /// Advances the reader to the next result when reading the results of batch SQL statements.
    abstract bool nextResult();

    /// Gets the name of the specified column.
    abstract string getName(int ordinal);

    /// Gets the column ordinal, given the name of the column.
    abstract int getOrdinal(string name);

    /// Returns a value as a single Variant containing the data for the specified column ordinal.
    abstract Variant getValue(int ordinal);

    /// Returns an array of Variant for each value in the row.
    abstract Variant[] getValues();

    /// Returns the value of the specified column as a boolean.
    bool getBool(int ordinal) { return getValue!bool(ordinal); }

    /// Returns the value of the specified column as a byte.
    byte getByte(int ordinal) { return getValue!byte(ordinal); }

    /// Returns the value of the specified column as a short (16-bit integer).
    short getShort(int ordinal) { return getValue!short(ordinal); }

    /// Returns the value of the specified column as an int (32-bit integer).
    int getInt(int ordinal) { return getValue!int(ordinal); }

    /// Returns the value of the specified column as a long (64-bit integer).
    long getLong(int ordinal) { return getValue!long(ordinal); }

    /// Returns the value of the specified column as a float.
    float getFloat(int ordinal) { return getValue!float(ordinal); }

    /// Returns the value of the specified column as a double.
    double getDouble(int ordinal) { return getValue!double(ordinal); }

    /// Returns the value of the specified column as a char.
    char getChar(int ordinal) { 
        auto str = getValue!string(ordinal);
        return str.length > 0 ? str[0] : '\0';
    }

    /// Returns the value of the specified column as an array of characters.
    char[] getChars(int ordinal) { return getValue!(char[])(ordinal); }

    /// Returns the value of the specified column as a string.
    string getString(int ordinal) { return getValue!string(ordinal); }

    /// Gets a value that indicates whether the column contains non-existent or missing values.
    abstract bool isNull(int ordinal);

    /// Attempts to convert the database value to specified template type.
    T getValue(T)(int ordinal)
    {
        return getValue(ordinal).coerce!T;
    }

    /// Closes the reader object.
    abstract void close();
}

/// SqlDataReader implementation using ODBC.
class SqlDataReader : DbDataReader
{
    private SqlCommand _command;
    private SQLHSTMT _stmt;
    private bool _isClosed;

    package this(SqlCommand command, SQLHSTMT stmt)
    {
        _command = command;
        _stmt = stmt;
        _isClosed = false;
    }

    override bool read()
    {
        if (_isClosed)
            throw new Exception("Invalid attempt to read when reader is closed.");

        auto ret = SQLFetch(_stmt);
        if (ret == 100) // SQL_NO_DATA
            return false;
        
        // SQL_SUCCESS = 0, SQL_SUCCESS_WITH_INFO = 1
        if (ret != 0 && ret != 1)
        {
            throw new Exception("Error fetching data.");
        }

        return true;
    }

    override bool nextResult()
    {
        if (_isClosed)
            throw new Exception("Invalid attempt to call nextResult when reader is closed.");

        auto ret = SQLMoreResults(_stmt);
        if (ret == 100) // SQL_NO_DATA
            return false;

        if (ret != 0 && ret != 1)
        {
            throw new Exception("Error advancing to next result.");
        }

        return true;
    }

    override string getName(int ordinal)
    {
        if (_isClosed)
            throw new Exception("Invalid attempt to read when reader is closed.");

        SQLCHAR[256] colName;
        SQLSMALLINT nameLen;
        auto ret = SQLDescribeCol(_stmt, cast(SQLUSMALLINT)(ordinal + 1), colName.ptr, cast(SQLSMALLINT)colName.length, &nameLen, null, null, null, null);
        if (ret != 0 && ret != 1)
        {
            throw new Exception("Failed to get column name.");
        }

        return cast(string)colName[0 .. nameLen].idup;
    }

    override int getOrdinal(string name)
    {
        if (_isClosed)
            throw new Exception("Invalid attempt to read when reader is closed.");

        SQLSMALLINT colCount;
        auto ret = SQLNumResultCols(_stmt, &colCount);
        if (ret != 0 && ret != 1)
        {
            throw new Exception("Failed to get column count.");
        }

        for (int i = 0; i < colCount; i++)
        {
            if (getName(i) == name)
            {
                return i;
            }
        }

        throw new Exception("Column not found: " ~ name);
    }

    override Variant getValue(int ordinal)
    {
        if (_isClosed)
            throw new Exception("Invalid attempt to read when reader is closed.");

        // ODBC C Types
        enum SQL_C_CHAR = 1;
        enum SQL_C_LONG = 4;
        enum SQL_C_SLONG = SQL_C_LONG - 20;
        enum SQL_C_DOUBLE = 8;
        enum SQL_C_BIT = -7;

        SQLSMALLINT dataType;
        auto ret = SQLDescribeCol(_stmt, cast(SQLUSMALLINT)(ordinal + 1), null, 0, null, &dataType, null, null, null);
        if (ret != 0 && ret != 1)
        {
            throw new Exception("Failed to get column type.");
        }

        SQLLEN indPtr;
        switch (dataType)
        {
            case SQL_BIT:
                ubyte bval;
                ret = SQLGetData(_stmt, cast(SQLUSMALLINT)(ordinal + 1), SQL_C_BIT, &bval, 0, &indPtr);
                if (ret == 100) return Variant(null);
                if (ret != 0 && ret != 1)
                    throw new Exception("Error retrieving data.");
                if (indPtr == SQL_NULL_DATA)
                    return Variant(null);
                return Variant(bval != 0);

            case SQL_INTEGER:
            case SQL_SMALLINT:
            case SQL_TINYINT:
                int val;
                ret = SQLGetData(_stmt, cast(SQLUSMALLINT)(ordinal + 1), SQL_C_SLONG, &val, 0, &indPtr);
                if (ret == 100) return Variant(null);
                if (ret != 0 && ret != 1)
                    throw new Exception("Error retrieving data.");
                if (indPtr == SQL_NULL_DATA)
                    return Variant(null);
                return Variant(val);
                
            case SQL_FLOAT:
            case SQL_REAL:
            case SQL_DOUBLE:
                double dval;
                ret = SQLGetData(_stmt, cast(SQLUSMALLINT)(ordinal + 1), SQL_C_DOUBLE, &dval, 0, &indPtr);
                if (ret == 100) return Variant(null);
                if (ret != 0 && ret != 1)
                    throw new Exception("Error retrieving data.");
                if (indPtr == SQL_NULL_DATA)
                    return Variant(null);
                return Variant(dval);

            case SQL_BIGINT:
                long lval;
                ret = SQLGetData(_stmt, cast(SQLUSMALLINT)(ordinal + 1), cast(SQLSMALLINT)SQL_C_SBIGINT, &lval, 0, &indPtr);
                if (ret == 100) return Variant(null);
                if (ret != 0 && ret != 1)
                    throw new Exception("Error retrieving data.");
                if (indPtr == SQL_NULL_DATA)
                    return Variant(null);
                return Variant(lval);

            default:
                // Check the exact length of the string data first
                SQLCHAR[1] dummy;
                ret = SQLGetData(_stmt, cast(SQLUSMALLINT)(ordinal + 1), SQL_C_CHAR, dummy.ptr, 0, &indPtr);
                
                if (ret == 100) return Variant(null); // SQL_NO_DATA
                if (ret != 0 && ret != 1)
                {
                    import std.conv : to;
                    throw new Exception("Error retrieving length. dataType: " ~ to!string(dataType) ~ " ret: " ~ to!string(ret));
                }
                    
                if (indPtr == SQL_NULL_DATA)
                    return Variant(null);

                // Allocate a buffer for the required length (+1 for null terminator)
                if (indPtr >= 0 && indPtr != -4) // -4 == SQL_NO_TOTAL
                {
                    char[] strBuf = new char[indPtr + 1];
                    SQLLEN finalLen;
                    ret = SQLGetData(_stmt, cast(SQLUSMALLINT)(ordinal + 1), SQL_C_CHAR, strBuf.ptr, cast(SQLLEN)strBuf.length, &finalLen);
                    
                    if (ret != 0 && ret != 1)
                        throw new Exception("Error retrieving string data.");
                        
                    return Variant(cast(string)strBuf[0 .. indPtr].idup);
                }

                // Fallback to chunking for drivers that return SQL_NO_TOTAL (-4)
                import std.array : appender;
                auto app = appender!string();
                bool notDone = true;
                while (notDone)
                {
                    SQLCHAR[8192] buf;
                    ret = SQLGetData(_stmt, cast(SQLUSMALLINT)(ordinal + 1), SQL_C_CHAR, buf.ptr, cast(SQLLEN)buf.length, &indPtr);
                    
                    if (ret == 100) break; // SQL_NO_DATA
                    if (ret != 0 && ret != 1)
                        throw new Exception("Error retrieving data.");
                        
                    if (indPtr == SQL_NULL_DATA)
                        return Variant(null);
                        
                    if (ret == 0) // SQL_SUCCESS
                    {
                        if (indPtr >= 0 && indPtr < buf.length)
                            app.put(cast(string)buf[0 .. indPtr].idup);
                        else
                        {
                            import core.stdc.string : strlen;
                            app.put(cast(string)buf[0 .. strlen(cast(char*)buf.ptr)].idup);
                        }
                        notDone = false;
                    }
                    else if (ret == 1) // SQL_SUCCESS_WITH_INFO
                    {
                        // SQL_SUCCESS_WITH_INFO means buffer is full, except the null terminator
                        app.put(cast(string)buf[0 .. buf.length - 1].idup);
                    }
                }
                return Variant(app.data);
        }
    }

    override Variant[] getValues()
    {
        if (_isClosed)
            throw new Exception("Invalid attempt to read when reader is closed.");

        SQLSMALLINT colCount;
        auto ret = SQLNumResultCols(_stmt, &colCount);
        if (ret != 0 && ret != 1)
        {
            throw new Exception("Failed to get column count.");
        }

        Variant[] values = new Variant[colCount];
        for (int i = 0; i < colCount; i++)
        {
            values[i] = getValue(i);
        }
        return values;
    }

    override bool isNull(int ordinal)
    {
        if (_isClosed)
            throw new Exception("Invalid attempt to read when reader is closed.");

        SQLLEN indPtr;
        enum SQL_C_CHAR = 1;
        SQLCHAR[1] dummy;
        auto ret = SQLGetData(_stmt, cast(SQLUSMALLINT)(ordinal + 1), SQL_C_CHAR, dummy.ptr, 0, &indPtr);
        
        if (ret != 0 && ret != 1)
        {
            throw new Exception("Error retrieving data for null check.");
        }
        
        return indPtr == SQL_NULL_DATA;
    }

    override void close()
    {
        if (!_isClosed)
        {
            if (_stmt !is null)
            {
                SQLCloseCursor(_stmt);
            }
            _isClosed = true;
        }
    }
}

unittest
{
    import std.process : environment;
    import std.format : format;
    import std.array : empty;
    import phobos.database.sql.connection;
    import phobos.database.sql.command;

    string driver = environment.get("ODBC_DRIVER");
    string server = environment.get("ODBC_SERVER");
    string database = environment.get("ODBC_DATABASE");
    string user = environment.get("ODBC_USER");
    string password = environment.get("ODBC_PASSWORD");

    if (driver.empty || server.empty || database.empty || user.empty || password.empty)
        return; // Skip test if env vars not set

    string connStr = format("DRIVER=%s;SERVER=%s;DATABASE=%s;UID=%s;PWD=%s;TrustServerCertificate=yes;", driver, server, database, user, password);

    auto conn = new SqlConnection(connStr);
    conn.open();
    scope(exit) conn.close();

    // Create table
    auto createCmd = new SqlCommand(conn, i"CREATE TABLE ##ttable_odbc_reader_test (id INT, name NVARCHAR(50), price FLOAT, code CHAR(1), amount BIGINT, count SMALLINT, flag TINYINT, ratio REAL, is_active BIT)");
    createCmd.executeNonQuery();
    createCmd.dispose();

    scope(exit)
    {
        auto dropCmd = new SqlCommand(conn, i"DROP TABLE IF EXISTS ##ttable_odbc_reader_test");
        dropCmd.executeNonQuery();
        dropCmd.dispose();
    }

    // Insert rows
    auto insert1 = new SqlCommand(conn, i"INSERT INTO ##ttable_odbc_reader_test (id, name, price, code, amount, count, flag, ratio, is_active) VALUES (1, 'Apple', 1.5, 'A', 10000000000, 10, 1, 1.2, 1)");
    insert1.executeNonQuery();
    insert1.dispose();

    auto insert2 = new SqlCommand(conn, i"INSERT INTO ##ttable_odbc_reader_test (id, name, price, code, amount, count, flag, ratio, is_active) VALUES (2, 'Banana', 2.3, 'B', 20000000000, 20, 2, 2.4, 0)");
    insert2.executeNonQuery();
    insert2.dispose();

    auto insert3 = new SqlCommand(conn, i"INSERT INTO ##ttable_odbc_reader_test (id, name, price, code, amount, count, flag, ratio, is_active) VALUES (3, 'Cherry', 3.7, 'C', 30000000000, 30, 3, 3.6, 1)");
    insert3.executeNonQuery();
    insert3.dispose();

    auto insert4 = new SqlCommand(conn, i"INSERT INTO ##ttable_odbc_reader_test (id, name, price, code, amount, count, flag, ratio, is_active) VALUES (4, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL)");
    insert4.executeNonQuery();
    insert4.dispose();

    // Select and read
    auto selectCmd = new SqlCommand(conn, i"SELECT id, name, price, code, amount, count, flag, ratio, is_active FROM ##ttable_odbc_reader_test ORDER BY id");
    auto reader = selectCmd.executeDataReader();
    scope(exit) reader.close();

    // Test columns
    assert(reader.getName(0) == "id");
    assert(reader.getName(1) == "name");
    assert(reader.getName(2) == "price");

    assert(reader.getOrdinal("id") == 0);
    assert(reader.getOrdinal("name") == 1);
    assert(reader.getOrdinal("price") == 2);

    // Advance to rows
    assert(reader.read() == true);
    
    // First row: 1, 'Apple', 1.5, 'A', 10000000000, 10, 1, 1.2, 1
    assert(reader.getInt(0) == 1);
    assert(reader.getString(1) == "Apple");
    assert(reader.getDouble(2) == 1.5);
    assert(reader.getChar(3) == 'A');
    assert(reader.getLong(4) == 10000000000);
    assert(reader.getShort(5) == 10);
    assert(reader.getByte(6) == 1);
    assert(cast(int)(reader.getFloat(7) * 10) == 12); // avoid exact float matching issues
    assert(reader.getBool(8) == true);

    assert(reader.read() == true);
    
    // Second row: 2, 'Banana', 2.3, etc.
    auto row2Vals = reader.getValues();
    assert(row2Vals.length == 9);
    assert(row2Vals[0].coerce!int == 2);
    assert(row2Vals[1].coerce!string == "Banana");
    assert(row2Vals[2].coerce!double == 2.3);
    assert(row2Vals[8].coerce!bool == false);

    assert(reader.read() == true);

    // Third row: 3, 'Cherry'
    assert(reader.getChars(3) == "C".dup); 
    assert(reader.getBool(8) == true);

    assert(reader.read() == true);
    
    // Fourth row: 4, NULL, NULL, etc.
    assert(reader.getInt(0) == 4);
    assert(reader.isNull(1) == true);
    assert(reader.isNull(2) == true);
    
    // Test that isNull doesn't consume the value if we subsequently read
    assert(reader.isNull(3) == true);
    auto nullVariant = reader.getValue(3);
    assert(nullVariant.type == typeid(typeof(null)));

    // Test boolean null
    assert(reader.isNull(8) == true);
    
    assert(reader.read() == false); // No more rows

    selectCmd.dispose();
}
