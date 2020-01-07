# -*- coding: utf-8 -*-
{% from "gitlab/map.jinja" import gitlab with context %}
{% if grains['os_family'] == 'Debian' %}
gitlab-runner repo:
  pkgrepo.managed:
    - humanname: gitlab-runner debian repo
    - file: /etc/apt/sources.list.d/gitlab-runner.list
    - name: deb https://packages.gitlab.com/runner/gitlab-runner/{{ grains['os']|lower }}/ {{ grains['oscodename'] }} main
    - key_url: https://packages.gitlab.com/runner/gitlab-runner/gpgkey
    - require_in:
      - pkg: gitlab-install_pkg

gitlab-install_pkg:
  pkg.installed:
    - name: gitlab-runner
{% else %}
gitlab-install_pkg:
  pkg.installed:
    - sources:
      - gitlab-runner: {{gitlab.runner.downloadpath}}
{% endif %}

gitlab-instal-pytoml:
  pkg.installed:
    - name: {{ gitlab.runner.pytoml }}

gitlab-runner-directory-services:
  file.directory:
    - name: {{ gitlab.runner.config_path }}/salt/services
    - makedirs: True

gitlab-runner-directory-runners:
  file.directory:
    - name: {{ gitlab.runner.config_path }}/salt/runners
    - makedirs: True

{% set installed_services = salt['file.find'](gitlab.runner.config_path ~ "/salt/services/", print="name") %}
{% set services = gitlab.runner.services | map(attribute='name')|list %}
{% set ss = installed_services | difference(services) %}
{% for uneeded_service in ss if ss[0]  %}
gitlab-runner-uninstall-uneeded_{{ uneeded_service }}:
  cmd.run:
    - name: gitlab-runner uninstall --service {{ uneeded_service }}
    - onlyif: gitlab-runner status --service {{ uneeded_service }} 

gitlab-runner-remove-uneeded_{{ uneeded_service }}:
  file.absent:
    - name: {{ gitlab.runner.config_path }}/salt/services/{{ uneeded_service }}

{% endfor %}
{%- for service in gitlab.runner.services %}
{%- set group = service.group|default(service.username, true) %}
{%- set home = service.home|default("/home/" ~ service.username, true) %}
{%- set working_directory = service.working_directory|default(home, true) %}
# reinstall service with proper user


gitlab-runner-uninstall_{{ service.name }}:
  cmd.run:
    - name: gitlab-runner uninstall --service {{ service.name }}
    - onlyif: gitlab-runner status --service {{ service.name }} 
    - onchanges:
      - file: gitlab-runner-install-template_{{ service.name }}


gitlab-runner-install-template_{{ service.name }}:
  file.managed:
    - name: {{ gitlab.runner.config_path }}/salt/services/{{service.name }}
    - mode: 700
    - source: salt://gitlab/scripts/install-service.sh.j2
    - template: jinja
    - context:
      service: {{ service | yaml }}
      working_directory: {{ working_directory }}

gitlab-runner-install_{{ service.name }}:
  cmd.script:
    - name: {{ gitlab.runner.config_path }}/salt/services/{{ service.name }}
    - require:
      - cmd: gitlab-runner-uninstall_{{ service.name }}
    - onchanges:
      - file: gitlab-runner-install-template_{{ service.name }}

gitlab-create_group_{{service.name }}_{{ group }}:
  group.present:
    - name: {{ group }}
    - system: True
    - require:
      - pkg: gitlab-install_pkg

gitlab-install_runserver_create_user_{{ service.name }}_{{ service.username }}:
  user.present:
    - name: {{service.username}}
    - shell: /bin/false
    - home: {{ home }}
    - groups:
      - {{ group }}
    - require:
      - group: gitlab-create_group_{{ service.name }}_{{ group }}

{% for runner in service.runners if service.runners %}
{% if salt['file.file_exists'](gitlab.runner.config_path ~ '/salt/runners/' ~  service.name ~ '_' ~ runner.name) %}
gitlab-runner-verify_{{ service.name }}_{{ runner.name }}:
  cmd.run:
    - name: gitlab-runner verify -c {{ gitlab.runner.config_path }}/{{ service.name }}.toml -n {{ runner.name }} --delete 2> /tmp/runner_verify

gitlab-runner-template-remove_{{ service.name }}_{{ runner.name }}:
  cmd.run:
    - name: rm {{ gitlab.runner.config_path }}/salt/runners/{{ service.name }}_{{ runner.name }}
    - onlyif: grep "Verifying runner... is removed" /tmp/runner_verify
    - require:
      - cmd: gitlab-runner-verify_{{ service.name }}_{{ runner.name }}

{% endif %}

gitlab-runner-template_{{ service.name }}_{{ runner.name }}:
  file.managed:
    - name: {{ gitlab.runner.config_path }}/salt/runners/{{ service.name }}_{{ runner.name }}
    - source: salt://gitlab/scripts/runner-register.sh.j2
    - template: jinja
    - mode: 700
    - context:
      runner: {{ runner | yaml }}
      service: {{ service | yaml }} 
    - require:
      - user: gitlab-install_runserver_create_user_{{ service.name }}_{{ service.username }}
    - require_in:
      - service: gitlab-service_{{ service.name}}

gitlab-runner-register_{{ service.name }}_{{ runner.name }}:
  cmd.script:
    - name: {{ gitlab.runner.config_path }}/salt/runners/{{ service.name }}_{{ runner.name }}
    - require:
      - user: gitlab-install_runserver_create_user_{{ service.name }}_{{ service.username }}
    - require_in:
      - service: gitlab-service_{{ service.name}}
    - onchanges:
      - file: gitlab-runner-template_{{ service.name }}_{{ runner.name }}

{% endfor %}
{% if salt['file.file_exists']( gitlab.runner.config_path ~ '/' ~ service.name  ~ '.toml') %}
{% set installed_runners = salt['slsutil.deserialize']('toml', salt['file.read']( gitlab.runner.config_path ~ '/' ~ service.name  ~ '.toml')).runners|map(attribute='name')|list if service.runners else [] %}
{% set new_runners =  service.runners | map(attribute='name')|list if service.runners %}
{% for to_remove_runner in  installed_runners | difference(new_runners) %}
gitlab-unregister-runner_{{ service.name }}_{{ to_remove_runner }}:
  cmd.run:
    - name: gitlab-runner unregister -c {{ gitlab.runner.config_path }}/{{ service.name }}.toml -n {{ to_remove_runner }}
{% endfor %}
{% endif %}

gitlab-service_{{ service.name }}:
  service.running:
    - name: {{ service.name }}
    - enable: True
    - require:
      - pkg: gitlab-install_pkg
    - watch:
      - cmd: gitlab-runner-install_{{ service.name }}
{% endfor %}
