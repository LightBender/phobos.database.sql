module phobos.database.sql.command;

import phobos.database.sql.connection;
import phobos.database.sql.transaction;
import phobos.database.sql.utility;
import phobos.database.sql.reader;
import etc.c.odbc.odbc64;
import core.interpolation;
import std.string;
import std.traits;
import std.exception;
import std.conv;
import std.meta;

/// Base class for SQL commands.
abstract class DbCommand
{
    @property abstract string commandText();
    @property abstract void commandText(string value);

    @property abstract DbConnection connection();
    @property abstract void connection(DbConnection value);

    @property abstract DbTransaction transaction();
    @property abstract void transaction(DbTransaction value);

    abstract int executeNonQuery();
    abstract Object executeScalar();
    abstract DbDataReader executeDataReader();
}

/// SqlCommand implementation using ODBC.
class SqlCommand : DbCommand
{
    private string _commandText;
    private SqlConnection _connection;
    private SqlTransaction _transaction;
    private SQLHSTMT _stmt;
    private void*[] _paramValues;
    private SQLLEN[] _paramIndicators;

    @disable this() {}

    /// IES constructor
    this(Args...)(SqlConnection connection, Args args)
        if (Args.length > 0 && is(Args[0] == InterpolationHeader))
    {
        _connection = connection;
        string sql;

        foreach (arg; args)
        {
            static if (is(typeof(arg) : InterpolatedLiteral!T, string T))
            {
                sql ~= T;
            }
            else static if (!is(typeof(arg) == InterpolationHeader) &&
                            !is(typeof(arg) : InterpolatedExpression!T, string T) &&
                            !is(typeof(arg) == InterpolationFooter))
            {
                sql ~= "?";
            }
        }
        
        _commandText = sql;
        prepare();

        size_t paramCount = 0;
        foreach (arg; args)
        {
            static if (!is(typeof(arg) : InterpolatedLiteral!A, string A) &&
                       !is(typeof(arg) : InterpolatedExpression!B, string B) &&
                       !is(typeof(arg) == InterpolationHeader) &&
                       !is(typeof(arg) == InterpolationFooter))
            {
                paramCount++;
            }
        }
        _paramValues.length = paramCount;
        _paramIndicators.length = paramCount;

        // Bind parameters
        SQLUSMALLINT paramIdx = 1;
        foreach (arg; args)
        {
            static if (!is(typeof(arg) : InterpolatedLiteral!A, string A) &&
                       !is(typeof(arg) : InterpolatedExpression!B, string B) &&
                       !is(typeof(arg) == InterpolationHeader) &&
                       !is(typeof(arg) == InterpolationFooter))
            {
                bindParameter(paramIdx++, arg);
            }
        }
    }

    @property override string commandText() { return _commandText; }
    @property override void commandText(string value) { _commandText = value; }

    @property override DbConnection connection() { return _connection; }
    @property override void connection(DbConnection value)
    {
        _connection = cast(SqlConnection)value;
    }

    @property override DbTransaction transaction() { return _transaction; }
    @property override void transaction(DbTransaction value)
    {
        _transaction = cast(SqlTransaction)value;
    }

    private void prepare()
    {
        if (_stmt !is null)
        {
            SQLFreeHandle(cast(SQLSMALLINT)3, _stmt);
            _stmt = null;
        }

        if (_connection is null || _connection.state != ConnectionState.open)
            throw new ODBCException("Connection must be open to prepare a command.");

        auto ret = SQLAllocHandle(cast(SQLSMALLINT)3, _connection.dbc(), &_stmt);
        checkError(cast(SQLSMALLINT)2, _connection.dbc(), ret, "SQLAllocHandle STMT");

        auto ret2 = SQLPrepare(_stmt, cast(SQLCHAR*)_commandText.ptr, cast(SQLINTEGER)_commandText.length);
        checkError(cast(SQLSMALLINT)3, _stmt, ret2, "SQLPrepare");
    }

    private void bindParameter(T)(SQLUSMALLINT ipar, ref T val)
    {
        SQLSMALLINT cType;
        SQLSMALLINT sqlType;
        SQLULEN columnSize;
        SQLPOINTER dataPtr;

        size_t idx = ipar - 1;

        static if (is(T == int))
        {
            cType = cast(SQLSMALLINT)-16; // SQL_C_SLONG / SQL_C_LONG
            sqlType = cast(SQLSMALLINT)4;   // SQL_INTEGER
            columnSize = 0;
            
            int* pVal = new int;
            *pVal = val;
            _paramValues[idx] = pVal;
            dataPtr = pVal;
            
            _paramIndicators[idx] = 0;
        }
        else static if (is(T == string))
        {
            cType = cast(SQLSMALLINT)1;    // SQL_C_CHAR
            sqlType = cast(SQLSMALLINT)12;  // SQL_VARCHAR
            columnSize = val.length;
            dataPtr = cast(SQLPOINTER)val.ptr;
            _paramValues[idx] = cast(void*)val.ptr;
            _paramIndicators[idx] = val.length;
        }
        else static if (is(T == double))
        {
            cType = cast(SQLSMALLINT)8;    // SQL_C_DOUBLE
            sqlType = cast(SQLSMALLINT)8;    // SQL_DOUBLE
            columnSize = 0;
            
            double* pVal = new double;
            *pVal = val;
            _paramValues[idx] = pVal;
            dataPtr = pVal;
            
            _paramIndicators[idx] = 0;
        }
        else
        {
            static assert(0, "Unsupported type for IES binding: " ~ T.stringof);
        }

        // We need to keep the values alive during execution if they are passed by ref from IES.
        // For strings, val.ptr should be fine if it's a GC-managed string.
        
        auto ret = SQLBindParameter(_stmt, ipar, 1, cType, sqlType, columnSize, 0, dataPtr, val.sizeof, &_paramIndicators[idx]);
        checkError(cast(SQLSMALLINT)3, _stmt, ret, "SQLBindParameter");
    }

    override int executeNonQuery()
    {
        if (_stmt is null) prepare();

        auto ret = SQLExecute(_stmt);
        checkError(cast(SQLSMALLINT)3, _stmt, ret, "SQLExecute");

        SQLLEN rowCount;
        auto ret2 = SQLRowCount(_stmt, &rowCount);
        checkError(cast(SQLSMALLINT)3, _stmt, ret2, "SQLRowCount");

        return cast(int)rowCount;
    }

    override Object executeScalar()
    {
        if (_stmt is null) prepare();

        auto ret = SQLExecute(_stmt);
        checkError(cast(SQLSMALLINT)3, _stmt, ret, "SQLExecute");

        auto ret2 = SQLFetch(_stmt);
        if (ret2 == 100) // SQL_NO_DATA
            return null;
        checkError(cast(SQLSMALLINT)3, _stmt, ret2, "SQLFetch");

        // For simplicity, let's assume we want the first column as a string or int
        // We'd need SQLGetData here.
        
        SQLCHAR[256] buf;
        SQLLEN indicator;
        auto ret3 = SQLGetData(_stmt, 1, cast(SQLSMALLINT)1, buf.ptr, 256, &indicator);
        checkError(cast(SQLSMALLINT)3, _stmt, ret3, "SQLGetData");

        if (indicator == -1) // SQL_NULL_DATA
            return null;

        return new BoxedString(cast(string)buf[0 .. indicator].idup);
    }

    override DbDataReader executeDataReader()
    {
        if (_stmt is null) prepare();

        auto ret = SQLExecute(_stmt);
        checkError(cast(SQLSMALLINT)3, _stmt, ret, "SQLExecute");

        return new SqlDataReader(this, _stmt);
    }

    ~this()
    {
        dispose();
    }

    void dispose()
    {
        if (_stmt !is null)
        {
            SQLFreeHandle(cast(SQLSMALLINT)3, _stmt);
            _stmt = null;
        }
    }
}

unittest
{
    import std.stdio : writeln;
    import std.process : environment;
    import std.format : format;
    // Test SQL string generation from IES
    // We can't easily test the full ODBC flow without a DB, 
    // but we can verify the SQL string construction.
    
    // Note: To test the IES constructor, we need a SqlConnection (even if not opened, 
    // though prepare() will fail if it's not open).
    // Let's mock a scenario where we just check _commandText if we bypass prepare().
    
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
    int id = 10;
    string name = "test";
    
    // Using a global temp table so it survives across different prepared statements 
    // inside the same connection.
    auto createCmd = new SqlCommand(conn, i"CREATE TABLE ##ttable_odbc_test (id INT, name NVARCHAR(16))");
    scope(exit) createCmd.dispose();
    createCmd.executeNonQuery();

    scope(exit)
    {
        auto dropCmd = new SqlCommand(conn, i"DROP TABLE IF EXISTS ##ttable_odbc_test");
        dropCmd.executeNonQuery();
        dropCmd.dispose();
    }

    auto insertCmd = new SqlCommand(conn, i"INSERT INTO ##ttable_odbc_test (id, name) VALUES ($(id), $(name))");
    scope(exit) insertCmd.dispose();
    assert(insertCmd.commandText == "INSERT INTO ##ttable_odbc_test (id, name) VALUES (?, ?)");

    int result = insertCmd.executeNonQuery();
    assert(result == 1);
}

class BoxedString
{
    string value;
    this(string v) { value = v; }
    override string toString() { return value; }
}
