module phobos.database.sql.command;

import phobos.database.sql.connection;
import phobos.database.sql.utility;
import etc.c.odbc.odbc64;
import std.array;
import std.conv;
import std.exception;

abstract class DbCommand
{
    @property abstract string commandText();

    @property abstract SqlConnection connection();

    abstract int executeNonQuery();

    abstract string executeScalar();
}

class SqlCommand : DbCommand
{
    private SqlConnection _conn;
    private string _commandText;
    private Object[] _parameters;
    private SQLHSTMT _stmt;

    this (Sequence...)(InterpolationHeader header, Sequence data, InterpolationFooter footer) {
        //TODO implement static for to process here
    }


    this(SqlConnection conn, string sql, Object[] parameters = null)
    {
        _conn = conn;
        _commandText = sql;
        _parameters = parameters;
    }

    @property override string commandText() { return _commandText; }

    @property void commandText(string text) { _commandText = text; }

    @property override SqlConnection connection() { return _conn; }

    private void prepare()
    {
        if (_stmt !is null) return;

        auto ret = SQLAllocHandle(cast(SQLSMALLINT)3, _conn.dbc(), &_stmt);
        checkError(cast(SQLSMALLINT)2, _conn.dbc(), ret, "SQLAllocHandle STMT");

        // Assume ? placeholders, count from parameters.length
        // TODO: replace $1 etc if needed

        auto ret2 = SQLPrepare(_stmt, cast(SQLCHAR*)_commandText.ptr, cast(SQLSMALLINT)-3);
        checkError(cast(SQLSMALLINT)3, _stmt, ret2, "SQLPrepare");
    }

    private void bindParams()
    {
        foreach (i, param; _parameters)
        {
            uint paramNum = cast(uint)i + 1;
            SQLSMALLINT ctype = SQL_CHAR;
            SQLSMALLINT sqltype = SQL_VARCHAR;
            SQLUINTEGER colSize = 255;
            SQLSMALLINT scale = 0;
            SQLPOINTER dataPtr = cast(SQLPOINTER) param.to!string.ptr;
            SQLLEN strLen_or_ind = SQL_LEN_DATA_AT_EXEC(0);
            SQLLEN* strLenPtr = &strLen_or_ind;
            // Note: for simplicity, use fixed length; adjust for dynamic

            auto ret = SQLBindParameter(_stmt, cast(SQLUSMALLINT)paramNum, SQL_PARAM_INPUT, ctype, sqltype, cast(SQLULEN)colSize, scale, dataPtr, 0, strLenPtr);
            checkError(cast(SQLSMALLINT)3, _stmt, ret, "SQLBindParameter");
        }
    }

    override int executeNonQuery()
    {
        prepare();
        bindParams();

        auto ret = SQLExecute(_stmt);
        checkError(cast(SQLSMALLINT)3, _stmt, ret, "SQLExecute");

        SQLLEN rows;
        auto ret2 = SQLRowCount(_stmt, &rows);
        checkError(cast(SQLSMALLINT)3, _stmt, ret2, "SQLRowCount");

        return cast(int)rows;
    }

    override string executeScalar()
    {
        prepare();
        bindParams();

        auto ret = SQLExecute(_stmt);
        checkError(cast(SQLSMALLINT)3, _stmt, ret, "SQLExecute");

        if (SQLFetch(_stmt) != SQL_SUCCESS && SQLFetch(_stmt) != SQL_SUCCESS_WITH_INFO)
            return null;

        SQLCHAR[256] buf;
        SQLLEN len;
        auto ret2 = SQLGetData(_stmt, 1, SQL_CHAR, buf.ptr, cast(SQLLEN)buf.sizeof, &len);
        checkError(cast(SQLSMALLINT)3, _stmt, ret2, "SQLGetData");

        return cast(string)(buf[0 .. len]).idup;
    }

    ~this()
    {
        if (_stmt !is null)
        {
            SQLFreeHandle(cast(SQLSMALLINT)3, _stmt);
            _stmt = null;
        }
    }
}