SELECT
    mi.time_4690 AS 'Time',
    m.message,
    m.data as 'Data',
    c.node,
    m.terminal,
    m.severity,
    m.priority,
    m.event,
    m.event_rule,
    m.quantity
FROM
    dbo.controllers c
INNER JOIN
    dbo.EDJCommonCompanyLookup a
ON
    (
        c.company_id = a.company_id)
INNER JOIN
    dbo.message_types m
ON
    (
        c.controller_ID = m.controller_ID)
INNER JOIN
    dbo.message_instances mi
ON
    (
        m.ID = mi.message_ID)
WHERE
mi.time_4690 BETWEEN '2026-02-25T15:38:28Z' AND '2026-03-04T15:38:28Z'
AND a.abbreviation = 'KS'
AND c.store = '0993'
AND m.terminal in ('144', '115')
AND c.node in ('FC','CC')
and m.message in ('X334')
ORDER BY
    mi.time_server DESC ;