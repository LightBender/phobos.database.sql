module phobos.database.sql.connection;

import phobos.database.sql.utility;
import phobos.database.sql.command;
import phobos.database.sql.transaction;
import odbc;
import etc.c.odbc;
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
        return unwrap(getInfoString(_dbc, SQL_DATABASE_NAME), "SQLGetInfo DATABASE_NAME");
    }

    @property override string dataSource()
    {
        enforceOpen();
        return unwrap(getInfoString(_dbc, SQL_DATA_SOURCE_NAME), "SQLGetInfo DATA_SOURCE_NAME");
    }

    @property override string serverVersion()
    {
        enforceOpen();
        return unwrap(getInfoString(_dbc, SQL_DBMS_VER), "SQLGetInfo DBMS_VER");
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
        _env = unwrap(allocEnv(), "SQLAllocHandle ENV");

        // Set ODBC version
        enforceOk(setEnvAttr(_env, SQL_ATTR_ODBC_VERSION, SQL_OV_ODBC3), "SQLSetEnvAttr");

        // Allocate DBC
        _dbc = unwrap(allocConnection(_env), "SQLAllocHandle DBC");

        // Driver connect
        unwrap(driverConnect(_dbc, _connectionString), "SQLDriverConnect");

        _state = ConnectionState.open;
    }

    override void close()
    {
        if (_dbc !is null)
        {
            enforceOk(disconnect(_dbc), "SQLDisconnect");
            enforceOk(freeHandle(SQL_HANDLE_DBC, _dbc), "SQLFreeHandle DBC");
            _dbc = null;
        }

        if (_env !is null)
        {
            enforceOk(freeHandle(SQL_HANDLE_ENV, _env), "SQLFreeHandle ENV");
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
    // dataSource (SQL_DATA_SOURCE_NAME) is the DSN, which is legitimately empty
    // when connecting via a DRIVER= connection string without a DSN.
    assert(!conn.serverVersion.empty);

    conn.close();
    assert(conn.state == ConnectionState.closed);
}

