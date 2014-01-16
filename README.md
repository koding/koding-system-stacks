Koding Server Stacks
======

Koding VM Images

This is the infrastructure used to create the VM tepmplates that run the VMs on Koding

This is run on an ubuntu raring server.

To install first ```sudo apt-get install lxc golang-go```
To setup your build env you will need to edit bin/build on and change build_ip to match your lxcbr0 interface and also edit inc/vmroot-config to match.

We accept pull requests to add new templates openly. 

We pull this repo to our testing build server every 24 hours and build the images. Before accepting a pull request we will place your template on our staging platform and tested.