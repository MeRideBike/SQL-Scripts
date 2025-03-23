-- Comprehensive Dependency Query for All Dependency Types in a Database

DECLARE @SearchTable NVARCHAR(128) = NULL; --'Type';  -- Replace with the table name or leave NULL for all tables
DECLARE @SearchColumn NVARCHAR(128) = NULL; --'RoleLevel';  -- Replace with the column name or leave NULL for all columns

-- Temporary table to capture all dependencies
IF OBJECT_ID('tempdb..#AllDependencies') IS NOT NULL DROP TABLE #AllDependencies;
CREATE TABLE #AllDependencies (
    TableName NVARCHAR(128),
    ColumnName NVARCHAR(128),
    DependencyName NVARCHAR(128),
    ObjectType NVARCHAR(128),
    DependencyType NVARCHAR(128)
);

-- 1. Direct dependencies from sys.sql_expression_dependencies
INSERT INTO #AllDependencies
SELECT 
    OBJECT_NAME(dep.referencing_id) AS DependencyName,
    col.name AS ColumnName,
    ref.name AS TableName,
    ref.type_desc AS ObjectType,
    'Direct Dependency' AS DependencyType
FROM sys.sql_expression_dependencies AS dep
JOIN sys.objects AS ref ON dep.referenced_id = ref.object_id
JOIN sys.columns AS col ON col.object_id = ref.object_id 
WHERE (ref.name = @SearchTable OR @SearchTable IS NULL)
  AND (col.name = @SearchColumn OR @SearchColumn IS NULL)
  AND ref.is_ms_shipped = 0;

-- 2. Text-based search for indirect dependencies in procedures, functions, and views
INSERT INTO #AllDependencies
SELECT 
    OBJECT_NAME(sm.object_id) AS DependencyName,
    @SearchColumn AS ColumnName,
    @SearchTable AS TableName,
    o.type_desc AS ObjectType,
    'Text Search Dependency' AS DependencyType
FROM sys.sql_modules AS sm
JOIN sys.objects AS o ON sm.object_id = o.object_id
WHERE (sm.definition LIKE '%' + @SearchTable + '.' + @SearchColumn + '%'
       OR sm.definition LIKE '%' + @SearchTable + '%')
      AND o.is_ms_shipped = 0;

-- 3. Foreign keys and cascade actions
INSERT INTO #AllDependencies
SELECT 
    OBJECT_NAME(fk.object_id) AS DependencyName,
    col.name AS ColumnName,
    OBJECT_NAME(fk.parent_object_id) AS TableName,
    'FOREIGN_KEY_CONSTRAINT' AS ObjectType,
    CASE 
        WHEN fk.delete_referential_action = 1 THEN 'Foreign Key (Cascade Delete)'
        WHEN fk.update_referential_action = 1 THEN 'Foreign Key (Cascade Update)'
        ELSE 'Foreign Key' 
    END AS DependencyType
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc ON fk.object_id = fkc.constraint_object_id
JOIN sys.columns AS col ON fkc.parent_column_id = col.column_id AND fkc.parent_object_id = col.object_id
WHERE (OBJECT_NAME(fk.parent_object_id) = @SearchTable OR @SearchTable IS NULL)
  AND (col.name = @SearchColumn OR @SearchColumn IS NULL);

-- 4. Indexes on the column
INSERT INTO #AllDependencies
SELECT 
    idx.name AS DependencyName,
    col.name AS ColumnName,
    OBJECT_NAME(idx.object_id) AS TableName,
    idx.type_desc AS ObjectType,
    'Index' AS DependencyType
FROM sys.indexes AS idx
JOIN sys.index_columns AS ic ON idx.index_id = ic.index_id AND idx.object_id = ic.object_id
JOIN sys.columns AS col ON ic.column_id = col.column_id AND ic.object_id = col.object_id
WHERE (OBJECT_NAME(idx.object_id) = @SearchTable OR @SearchTable IS NULL)
  AND (col.name = @SearchColumn OR @SearchColumn IS NULL);

-- 5. Check constraints
INSERT INTO #AllDependencies
SELECT 
    cc.name AS DependencyName,
    col.name AS ColumnName,
    OBJECT_NAME(cc.parent_object_id) AS TableName,
    'CHECK_CONSTRAINT' AS ObjectType,
    'Check Constraint' AS DependencyType
FROM sys.check_constraints AS cc
JOIN sys.columns AS col ON cc.parent_column_id = col.column_id AND cc.parent_object_id = col.object_id
WHERE (OBJECT_NAME(cc.parent_object_id) = @SearchTable OR @SearchTable IS NULL)
  AND (col.name = @SearchColumn OR @SearchColumn IS NULL);

-- 6. Primary keys and unique constraints
INSERT INTO #AllDependencies
SELECT 
    kc.name AS DependencyName,
    col.name AS ColumnName,
    OBJECT_NAME(kc.parent_object_id) AS TableName,
    kc.type_desc AS ObjectType,
    CASE 
        WHEN kc.type = 'PK' THEN 'Primary Key'
        ELSE 'Unique Constraint' 
    END AS DependencyType
FROM sys.key_constraints AS kc
JOIN sys.index_columns AS ic ON kc.unique_index_id = ic.index_id AND kc.parent_object_id = ic.object_id
JOIN sys.columns AS col ON ic.column_id = col.column_id AND ic.object_id = col.object_id
WHERE (OBJECT_NAME(kc.parent_object_id) = @SearchTable OR @SearchTable IS NULL)
  AND (col.name = @SearchColumn OR @SearchColumn IS NULL);

-- Output all dependencies found
SELECT DISTINCT * FROM #AllDependencies ORDER BY TableName, ColumnName, DependencyType;

-- Clean up
DROP TABLE #AllDependencies;
