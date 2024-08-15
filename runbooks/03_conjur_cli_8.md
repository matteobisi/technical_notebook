# Conjur cli 8 

## Description
Conjur is an enterprise secrets managed and it's evolving over time in a good way.  
From time to time they are also upgrading the cli, every upgrade something changes,  
I need to keep a little chatsheat for personal usage.  
Naturally there is an offial [docs](https://docs.cyberark.com/conjur-enterprise/latest/en/Content/Developer/CLI/cli-commands.htm?tocpath=Developer%7CConjur%20CLI%7CConjur%20CLI%20command%20reference%7C_____0) , but it's not always super clear so  
I'll trak here some pratical examples.    


## Authentication commands
All the commeands related to authentications phase
*INIT*
```
conjur init –url <Conjur URL>
--ca-cert: to add the certificate path.
--self-signed: if using self-signed certificates.
eg  conjur init -url my.conjur.com --self-signed
```

*LOGIN*
```
conjur login
-i: to specify username
-p: to specify password

eg  conjur login -i admin
```
*LOGOUT*
```
conjur logout

eg  conjur logout
```

*whoami*
```
to be sure about current logged user
conjur whoami
```

## Show resources
One of the most usefull command in Cli8 is teh show command to extract info  
from Conjur quickly  

*resource*
```
conjur resource show conjuraccount:object:value

eg
conjur resource show myconjurorg:policy:root
conjur resource show myconjurorg:user:utente
conjur resource show myconjurorg:host:test/app/test-app
```
