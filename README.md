# Unikraft Cloud Script

This script deploys unikraft generated KVM target unikernels on **Google Cloud Platform**

## Installation

Copy the script to `/usr/local/bin` 

```
sudo cp deploy-unikraft-gcp.sh /usr/local/bin/
```
Please make sure that `/usr/local/bin` is in your `PATH`

**OR**

You can directly run the script like - 

```bash
./<path/of/deploy-unikraft-gcp.sh>
Eg, ./deploy-unikraft-gcp.sh (If the script is in current dir)
```


## Usage
Please make sure that you have a working google cloud account.  
If not, please create one (click [here](https://cloud.google.com/)).
 

```
usage: ./deploy-unikraft-gcp.sh [-h] [-v] -k <unikernel> -b <bucket> [-p <config-path>] [-n <name>]
        [-z <zone>] [-i <instance-type>] [-t <tag>] [-s]

Mandatory Args:
<unikernel>: 	  Name/Path of the unikernel.(Please use "KVM" target images) 
<bucket>: 	      GCP bucket name

Optional Args:
<name>: 	      Image name to use on the cloud (default: unikraft)
<zone>: 	      GCP zone (default: europe-west3-c)
<instance-type>:  Specify the type of the machine on which you wish to deploy the unikernel (default: f1-micro) 
<tag>:		      Tag is used to identify the instances when adding network firewall rules (default: http-server)
<-v>: 		      Turns on verbose mode
<-s>: 		      Automatically starts an instance on the cloud


```

## Contributing
For major changes, please open an issue first to discuss what you would like to change.
