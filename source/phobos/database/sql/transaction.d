module phobos.database.sql.transaction;

import phobos.database.sql.connection;
import phobos.database.sql.utility;
import etc.c.odbc.odbc64;
import std.exception;

enum IsolationLevel
{
    unspecified,
    chaos,
    readUncommitted,
    readCommitted,
    repeatableRead,
    serializable,
    snapshot
}

abstract class DbTransaction
{
    @property abstract IsolationLevel isolationLevel();

    @property abstract DbConnection connection();

    abstract void commit();

    abstract void rollback();

}

class SqlTransaction : DbTransaction
{
    private SqlConnection _connection;
    private IsolationLevel _level = IsolationLevel.unspecified;
    private bool _committed;

    this(SqlConnection connection, IsolationLevel level = IsolationLevel.unspecified)
    {
        _connection = connection;
        _level = level;

        // Disable autocommit
        auto ret = SQLSetConnectAttr(_connection.dbc(), 90, cast(SQLPOINTER)0, 0);
        checkError(cast(SQLSMALLINT)2, _connection.dbc(), ret, "SQLSetConnectAttr AUTOCOMMIT OFF");

        // Set isolation level
        uint iso = odbcIsolationLevel(_level);
        auto ret2 = SQLSetConnectAttr(_connection.dbc(), 88, cast(SQLPOINTER)iso, 0);
        checkError(cast(SQLSMALLINT)2, _connection.dbc(), ret2, "SQLSetConnectAttr TXN_ISOLATION");
    }

    private uint odbcIsolationLevel(IsolationLevel l)
    {
        final switch (l)
        {
            case IsolationLevel.unspecified: return 0;
            case IsolationLevel.readUncommitted: return 1;
            case IsolationLevel.readCommitted: return 2;
            case IsolationLevel.repeatableRead: return 3;
            case IsolationLevel.serializable: return 4;
            case IsolationLevel.chaos, IsolationLevel.snapshot: return 4;
        }
    }

    @property override IsolationLevel isolationLevel() { return _level; }

    @property override DbConnection connection() { return _connection; }

    override void commit()
    {
        if (_committed) throw new Exception("Transaction already committed or rolled back.");

        auto ret = SQLEndTran(cast(SQLSMALLINT)2, _connection.dbc(), cast(SQLSMALLINT)1);
        checkError(cast(SQLSMALLINT)2, _connection.dbc(), ret, "SQLEndTran COMMIT");

        // Re-enable autocommit
        auto ret2 = SQLSetConnectAttr(_connection.dbc(), 90, cast(SQLPOINTER)1, 0);
        checkError(cast(SQLSMALLINT)2, _connection.dbc(), ret2, "SQLSetConnectAttr AUTOCOMMIT ON");

        _committed = true;
    }

    override void rollback()
    {
        if (_committed) throw new Exception("Transaction already committed or rolled back.");

        auto ret = SQLEndTran(cast(SQLSMALLINT)2, _connection.dbc(), cast(SQLSMALLINT)0);
        checkError(cast(SQLSMALLINT)2, _connection.dbc(), ret, "SQLEndTran ROLLBACK");

        // Re-enable autocommit
        auto ret2 = SQLSetConnectAttr(_connection.dbc(), 90, cast(SQLPOINTER)1, 0);
        checkError(cast(SQLSMALLINT)2, _connection.dbc(), ret2, "SQLSetConnectAttr AUTOCOMMIT ON");

        _committed = true;
    }

    ~this()
    {
        if (!_committed) rollback();
    }
}
