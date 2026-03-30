module phobos.database.sql.connection;

import phobos.database.sql.utility;
import phobos.database.sql.command;
import phobos.database.sql.transaction;
import etc.c.odbc.odbc64;
import std.string;
import std.array;
import std.exception;

/// Connection state enum mirroring ADO.NET ConnectionState.
enum ConnectionState : int
{
    closed     = 0,
    open       = 1,
    connecting = 2,
    executing  = 4,
    fetching   = 8,
    broken     = 16
}

abstract class DbConnection
{
    /// Gets or sets the connection string.
    @property abstract string connectionString();

    /// Gets the connection timeout value (default 15 seconds).
    @property abstract int connectionTimeout();

    /// Gets the name of the current database.
    @property abstract string database();

    /// Gets the name of the data source.
    @property abstract string dataSource();

    /// Gets the server version.
    @property abstract string serverVersion();

    /// Gets the current state.
    @property abstract ConnectionState state();

    /// Opens the connection.
    abstract void open();

    /// Closes the connection.
    abstract void close();

    /// Creates a command object.
    abstract DbCommand createCommand(Args...)(SqlConnection connection, Args args);

    /// Begins a transaction.
    abstract DbTransaction beginTransaction(IsolationLevel level = IsolationLevel.unspecified);

}

class SqlConnection : DbConnection
{
    private string _connectionString;
    private ConnectionState _state = ConnectionState.closed;
    private SQLHENV _env;
    private SQLHDBC _dbc;

    package @property SQLHDBC dbc() { return _dbc; }

    private void enforceOpen()
    {
        if (_state != ConnectionState.open)
            throw new ODBCException("Connection must be open for this operation.");
    }

    @property override string connectionString() { return _connectionString; }

    @property void connectionString(string cs)
    {
        if (_state != ConnectionState.closed)
            throw new ODBCException("Connection string can only be set when closed.");
        _connectionString = cs;

    }

    @property override int connectionTimeout() { return 15; }

    @property override string database()
    {
        enforceOpen();
        SQLCHAR[256] dbName;
        SQLSMALLINT len;
        auto ret = SQLGetInfo(_dbc, 16, dbName.ptr, cast(SQLSMALLINT)256, &len);
        checkError(cast(SQLSMALLINT)2, _dbc, ret, "SQLGetInfo DATABASE_NAME");
        return cast(string)(dbName[0 .. len]).idup;
    }

    @property override string dataSource()
    {
        enforceOpen();
        SQLCHAR[256] dsName;
        SQLSMALLINT len;
        auto ret = SQLGetInfo(_dbc, 110, dsName.ptr, cast(SQLSMALLINT)256, &len);
        checkError(cast(SQLSMALLINT)2, _dbc, ret, "SQLGetInfo DATA_SOURCE_NAME");
        return cast(string)(dsName[0 .. len]).idup;
    }

    @property override string serverVersion()
    {
        enforceOpen();
        SQLCHAR[256] ver;
        SQLSMALLINT len;
        auto ret = SQLGetInfo(_dbc, 18, ver.ptr, cast(SQLSMALLINT)256, &len);
        checkError(cast(SQLSMALLINT)2, _dbc, ret, "SQLGetInfo DBMS_VER");
        return cast(string)(ver[0 .. len]).idup;
    }

    @property override ConnectionState state() { return _state; }

    this(string connectionString)
    {
        this.connectionString = connectionString;
    }

    override void open()
    {
        if (_state != ConnectionState.closed)
            throw new ODBCException("Invalid operation. The connection is not closed.");

        _state = ConnectionState.connecting;

        // Allocate environment
        SQLHENV env;
        auto ret1 = SQLAllocHandle(cast(SQLSMALLINT)1, cast(void*)0, &env);
        checkError(cast(SQLSMALLINT)1, cast(void*)0, ret1, "SQLAllocHandle ENV");
        _env = env;

        // Set ODBC version
        auto ret2 = SQLSetEnvAttr(_env, 200, cast(SQLPOINTER)3, 0);
        checkError(cast(SQLSMALLINT)1, _env, ret2, "SQLSetEnvAttr");

        // Allocate DBC
        SQLHDBC dbc;
        auto ret3 = SQLAllocHandle(cast(SQLSMALLINT)2, _env, &dbc);
        checkError(cast(SQLSMALLINT)1, _env, ret3, "SQLAllocHandle DBC");
        _dbc = dbc;

        // Driver connect
        auto ret4 = SQLDriverConnect(_dbc, null, cast(SQLCHAR*)_connectionString.ptr, cast(SQLSMALLINT)-3, null, 0, null, 0);
        checkError(cast(SQLSMALLINT)2, _dbc, ret4, "SQLDriverConnect");

        _state = ConnectionState.open;
    }

    override void close()
    {
        if (_dbc !is null)
        {
            auto ret = SQLDisconnect(_dbc);
            checkError(cast(SQLSMALLINT)2, _dbc, ret, "SQLDisconnect");
        }

        if (_dbc !is null)
        {
            auto ret = SQLFreeHandle(cast(SQLSMALLINT)2, _dbc);
            checkError(cast(SQLSMALLINT)2, _dbc, ret, "SQLFreeHandle DBC");
            _dbc = null;
        }

        if (_env !is null)
        {
            auto ret = SQLFreeHandle(cast(SQLSMALLINT)1, _env);
            checkError(cast(SQLSMALLINT)1, _env, ret, "SQLFreeHandle ENV");
            _env = null;
        }

        _state = ConnectionState.closed;
    }

    ~this()
    {
        if (_state != ConnectionState.closed)
            close();
    }

    override DbCommand createCommand(Args...)(Args args)
    {
        return new SqlCommand(this, args);
    }

    override DbTransaction beginTransaction(IsolationLevel level = IsolationLevel.unspecified)
    {
        enforceOpen();
        return new SqlTransaction(this, level);
    }
}

unittest
{
    import std.process : environment;
    import std.format : format;

    string driver = environment.get("ODBC_DRIVER");
    string server = environment.get("ODBC_SERVER");
    string database = environment.get("ODBC_DATABASE");
    string user = environment.get("ODBC_USER");
    string password = environment.get("ODBC_PASSWORD");

    if (driver.empty || server.empty || database.empty || user.empty || password.empty)
        return; // Skip test if env vars not set

    string connStr = format("DRIVER=%s;SERVER=%s;DATABASE=%s;UID=%s;PWD=%s;TrustServerCertificate=yes;", driver, server, database, user, password);

    auto conn = new SqlConnection(connStr);
    scope (exit) {
        if (conn.state != ConnectionState.closed)
            conn.close();
    }

    assert(conn.state == ConnectionState.closed);

    conn.open();
    scope (exit) conn.close();

    assert(conn.state == ConnectionState.open);
    assert(!conn.database.empty);
    assert(!conn.dataSource.empty);
    assert(!conn.serverVersion.empty);

    conn.close();
    assert(conn.state == ConnectionState.closed);
}

