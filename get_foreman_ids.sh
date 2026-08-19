#!/bin/bash

###############################################################################
# FOREMAN / AWX HOST PROVISIONING VARIABLES
#
# Operating System Selection:
#
# 1 = CentOS Linux 7
# 2 = Rocky Linux 8.10
# 3 = Rocky Linux 9.2
# 4 = Rocky Linux 9.8
#
# Disk Layout:
#
# single = Single Disk Installation
# raid   = RAID1 Installation
#
###############################################################################


###############################################################################
# AWX SURVEY VARIABLES
###############################################################################

# OS Selection
hostgroup: "{{ hostgroup | default('1', true) }}"

# Disk Selection
disk_layout: "{{ disk_layout | default('raid', true) }}"


###############################################################################
# FOREMAN SUBNET NAME
#
# 1 = CentOS 7 subnet
# 2 = Rocky 8.10 subnet
# 3 = Rocky 9.2 subnet
# 4 = Rocky 9.8 subnet
###############################################################################

subnet_name: >-
  {{
    {
      '1': 'vgs-subnet-centos',
      '2': 'vgs-subnet-rockyos',
      '3': 'vgs-subnet-rockyos',
      '4': 'vgs-subnet-rockyos'
    }[hostgroup | string]
  }}


###############################################################################
# FOREMAN SUBNET ID
###############################################################################

subnet_id: >-
  {{
    {
      '1': 1,
      '2': 2,
      '3': 2,
      '4': 2
    }[hostgroup | string]
  }}


###############################################################################
# FOREMAN HOSTGROUP ID
#
# Lookup Results:
#
# CentOSLinux7-RAID             = 1
# RockyLinux8.10-RAID           = 2
# RockyLinux9.2-RAID            = 3
# RockyLinux9.8-RAID            = 4
#
# CentOSLinux7-SingleDisk       = 5
# RockyLinux8.10-SingleDisk     = 6
# RockyLinux9.2-SingleDisk      = 7
# RockyLinux9.8-SingleDisk      = 8
###############################################################################

hostgroup_id: >-
  {{
    {
      '1-raid': 1,
      '2-raid': 2,
      '3-raid': 3,
      '4-raid': 4,

      '1-single': 5,
      '2-single': 6,
      '3-single': 7,
      '4-single': 8
    }[hostgroup | string ~ '-' ~ disk_layout | string]
  }}


###############################################################################
# FOREMAN OPERATING SYSTEM ID
#
# CentOSLinux7-RAID 7       = 2
# RockyLinux8.10-RAID 8.10  = 4
# RockyLinux9.2-RAID 9.2    = 6
# RockyLinux9.8-RAID 9.8    = 8
###############################################################################

operatingsystem_id: >-
  {{
    {
      '1': 2,
      '2': 4,
      '3': 6,
      '4': 8
    }[hostgroup | string]
  }}


###############################################################################
# FOREMAN INSTALLATION MEDIUM ID
#
# CentOS 7 Remote    = 15
# Rocky 8 Remote     = 16
# Rocky 9.2 Remote   = 17
# Rocky 9 Remote     = 18
###############################################################################

medium_id: >-
  {{
    {
      '1': 15,
      '2': 16,
      '3': 17,
      '4': 18
    }[hostgroup | string]
  }}


###############################################################################
# PARTITION TABLE
#
# Kickstart default = 126
###############################################################################

ptable_id: 126


###############################################################################
# ARCHITECTURE
#
# x86_64 = 1
###############################################################################

architecture_id: 1


###############################################################################
# KATELLO CONTENT VIEW
#
# IMPORTANT:
# Update IDs 3 and 4 below if your Rocky 9.2 / Rocky 9.8 Content View IDs
# are different in your Foreman server.
###############################################################################

content_view_id: >-
  {{
    {
      '1': 1,
      '2': 3,
      '3': 4,
      '4': 5
    }[hostgroup | string]
  }}


###############################################################################
# KATELLO LIFECYCLE ENVIRONMENT
###############################################################################

lifecycle_environment_id: 1


###############################################################################
# PXE SETTINGS
###############################################################################

pxe_loader: "Grub2 UEFI"

build: true


###############################################################################
# DEBUG / VALIDATION
###############################################################################

foreman_selection_summary:
  selected_os: >-
    {{
      {
        '1': 'CentOS Linux 7',
        '2': 'Rocky Linux 8.10',
        '3': 'Rocky Linux 9.2',
        '4': 'Rocky Linux 9.8'
      }[hostgroup | string]
    }}

  selected_disk_layout: "{{ disk_layout }}"

  selected_subnet: "{{ subnet_name }}"

  selected_subnet_id: "{{ subnet_id }}"

  selected_hostgroup_id: "{{ hostgroup_id }}"

  selected_operatingsystem_id: "{{ operatingsystem_id }}"

  selected_medium_id: "{{ medium_id }}"

  selected_ptable_id: "{{ ptable_id }}"

  selected_architecture_id: "{{ architecture_id }}"

  selected_content_view_id: "{{ content_view_id }}"

  selected_lifecycle_environment_id: "{{ lifecycle_environment_id }}"
