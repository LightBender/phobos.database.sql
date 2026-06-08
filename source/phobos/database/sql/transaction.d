module phobos.database.sql.transaction;

import phobos.database.sql.connection;
import phobos.database.sql.utility;
import odbc;
import etc.c.odbc;
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
        enforceOk(setConnectAttr(_connection.dbc(), SQL_ATTR_AUTOCOMMIT,
                cast(SQLUINTEGER)SQL_AUTOCOMMIT_OFF), "SQLSetConnectAttr AUTOCOMMIT OFF");

        // Set isolation level
        enforceOk(setConnectAttr(_connection.dbc(), SQL_ATTR_TXN_ISOLATION,
                odbcIsolationLevel(_level)), "SQLSetConnectAttr TXN_ISOLATION");
    }

    private SQLUINTEGER odbcIsolationLevel(IsolationLevel l)
    {
        final switch (l)
        {
            case IsolationLevel.unspecified: return 0;
            case IsolationLevel.readUncommitted: return SQL_TXN_READ_UNCOMMITTED;
            case IsolationLevel.readCommitted: return SQL_TXN_READ_COMMITTED;
            case IsolationLevel.repeatableRead: return SQL_TXN_REPEATABLE_READ;
            case IsolationLevel.serializable: return SQL_TXN_SERIALIZABLE;
            case IsolationLevel.chaos, IsolationLevel.snapshot: return SQL_TXN_SERIALIZABLE;
        }
    }

    @property override IsolationLevel isolationLevel() { return _level; }

    @property override DbConnection connection() { return _connection; }

    override void commit()
    {
        if (_committed) throw new Exception("Transaction already committed or rolled back.");

        enforceOk(endTran(SQL_HANDLE_DBC, _connection.dbc(), SQL_COMMIT), "SQLEndTran COMMIT");

        // Re-enable autocommit
        enforceOk(setConnectAttr(_connection.dbc(), SQL_ATTR_AUTOCOMMIT,
                cast(SQLUINTEGER)SQL_AUTOCOMMIT_ON), "SQLSetConnectAttr AUTOCOMMIT ON");

        _committed = true;
    }

    override void rollback()
    {
        if (_committed) throw new Exception("Transaction already committed or rolled back.");

        enforceOk(endTran(SQL_HANDLE_DBC, _connection.dbc(), SQL_ROLLBACK), "SQLEndTran ROLLBACK");

        // Re-enable autocommit
        enforceOk(setConnectAttr(_connection.dbc(), SQL_ATTR_AUTOCOMMIT,
                cast(SQLUINTEGER)SQL_AUTOCOMMIT_ON), "SQLSetConnectAttr AUTOCOMMIT ON");

        _committed = true;
    }

    ~this()
    {
        if (!_committed) rollback();
    }
}
