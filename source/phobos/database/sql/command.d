module phobos.database.sql.command;

import core.interpolation;

abstract class DbCommand
{
    /// The text of the command.
    @property abstract string commandText();

    /// Executes the command without returning results.
    abstract int executeNonQuery();
    // TODO: executeReader, executeScalar, Parameters, Connection prop, etc.
}

class SqlCommand : DbCommand
{
    private string _commandText;

    @property override string commandText() { return _commandText; }

    @property void commandText(string text) { _commandText = text; }

    override int executeNonQuery()
    {
        // TODO: Implement ODBC execution
        return 0;
    }
}