SELECT 
    cm.abbreviation + right(c.store, 3) as Store,
    c.node,
    left(right(f.name, 7), 3) as lane,
    fh.modification_time
FROM dbo.controllers c 
INNER JOIN dbo.fcd_file_history fh 
        ON ( c.controller_ID = fh.controllerID) 
INNER JOIN dbo.fcd_file f 
        ON ( fh.fileID = f.fileID) 
INNER JOIN [EDJCommon].[dbo].[companies] cm
        on ( cm.company_id = c.company_id )
where
        f.name like 'c:\ADX_STLD\ADXTM%'
        and f.name != 'C:\ADX_STLD\ADXTMCLN.LOG'
        
        and cm.abbreviation like 'ru'
        and c.store like '0222'
        
        and fh.current_version = 'true'
        and fh.reason_file_deleted = 'false'
order by Store, lane asc