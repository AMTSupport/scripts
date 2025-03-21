net stop MSDTC
net stop "Rockend PrintMail Discovery" /yes
net stop ASIndexer
net stop RockendTrustAccounting
net start MSDTC
net start "Rockend PrintMail Discovery"
net start ASIndexer
net start RockendTrustAccounting
