CREATE TABLE IF NOT EXISTS `advent_calendar` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) NOT NULL,
  `day` int(11) NOT NULL,
  `opened_date` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_player_day` (`citizenid`, `day`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

