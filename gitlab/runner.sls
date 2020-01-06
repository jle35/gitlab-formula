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

{%- for service_name, service in gitlab.runner.items() %}
{%- set group = service.group|default(service.username, true) %}
{%- set home = service.home|default("/home/" ~ service.username, true) %}
{%- set working_directory = service.working_directory|default(home, true) %}

# reinstall service with proper user

gitlab-runner-uninstall_{{ service_name }}:
  cmd.run:
    - name: gitlab-runner uninstall --service {{ service_name }}
    - onlyif: gitlab-runner status --service {{ service_name }} 
    - onchanges:
      - file: gitlab-runner-install-template_{{ service_name }}


gitlab-runner-install-template_{{ service_name }}:
  file.managed:
    - name: /etc/gitlab-runner/install-{{service_name }}.sh
    - mode: 700
    - source: salt://gitlab/scripts/install-service.sh.j2
    - template: jinja
    - context:
      service: {{ service | yaml }}
      service_name: {{ service_name }}
      working_directory: {{ working_directory }}

gitlab-runner-install_{{ service_name }}:
  cmd.script:
    - name: /etc/gitlab-runner/install-{{ service_name }}.sh
    - require:
      - cmd: gitlab-runner-uninstall_{{ service_name }}
    - onchanges:
      - file: gitlab-runner-install-template_{{ service_name }}

gitlab-create_group_{{service_name }}_{{ group }}:
  group.present:
    - name: {{ group }}
    - system: True
    - require:
      - pkg: gitlab-install_pkg

gitlab-install_runserver_create_user_{{ service_name }}_{{ service.username }}:
  user.present:
    - name: {{service.username}}
    - shell: /bin/false
    - home: {{ home }}
    - groups:
      - {{ group }}
    - require:
      - group: gitlab-create_group_{{ service_name }}_{{ group }}

{% for runner in service.runners if service.runners %}
gitlab-runner-template_{{ service_name }}_{{ runner.name }}:
  file.managed:
    - name: /etc/gitlab-runner/runner-register-{{ service_name }}_{{ runner.name }}
    - source: salt://gitlab/scripts/runner-register.sh.j2
    - template: jinja
    - mode: 700
    - context:
      runner: {{ runner | yaml }}
      service_name: {{ service_name }}
    - require:
      - user: gitlab-install_runserver_create_user_{{ service_name }}_{{ service.username }}
    - require_in:
      - service: gitlab-service_{{ service_name}}

gitlab-runner-unregister_{{ service_name }}_{{ runner.name }}:
  cmd.run:
    - name: gitlab-runner unregister -n {{ runner.name }} -c /etc/gitlab-runner/{{ service_name }}.toml
    - success_retcodes:
      - 1
    - onchanges:
      - file: gitlab-runner-template_{{ service_name }}_{{ runner.name }}
    - require_in:
      - cmd: gitlab-runner-register_{{ service_name }}_{{ runner.name }}

gitlab-runner-register_{{ service_name }}_{{ runner.name }}:
  cmd.script:
    - name: /etc/gitlab-runner/runner-register-{{ service_name }}_{{ runner.name }}
    - require:
      - user: gitlab-install_runserver_create_user_{{ service_name }}_{{ service.username }}
    - require_in:
      - service: gitlab-service_{{ service_name}}
    - onchanges:
      - file: gitlab-runner-template_{{ service_name }}_{{ runner.name }}
{% endfor %}

gitlab-service_{{ service_name }}:
  service.running:
    - name: {{ service_name }}
    - enable: True
    - require:
      - pkg: gitlab-install_pkg
    - watch:
      - cmd: gitlab-runner-install_{{ service_name }}
{% endfor %}

{% set installed_runners = salt['file.find']("/etc/gitlab-runner/", regex="runner-register") %}
{% for i_runner in installed_runners %}

  {%- set keep_alive = {'value': False} %}
  {%- set i_runner_name = i_runner.split('runner-register-')[1].split('_')[1] %}
  {%- set i_runner_service = i_runner.split('runner-register-')[1].split('_')[0] %}
  {%- for service_name, service in gitlab.runner.items() %}
    {%- for runner in service.runners if service.runners %}
      {%- if runner.name == i_runner_name %}
        {%- if keep_alive.update({'value': True}) %} {% endif %}
      {%- endif %}
    {%- endfor %}
  {%- endfor %}
  {%- if keep_alive.value == False %}
giitlab-runner-unregister_{{ i_runner_name }}:
  cmd.run:
    - name: gitlab-runner unregister -n {{ i_runner_name }} -c /etc/gitlab-runner/{{ i_runner_service }}.toml

{{ i_runner}}:
  file.absent

  {%- endif %}
{%- endfor %}
