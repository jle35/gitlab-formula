# vim: sts=2 ts=2 sw=2 et ai
#
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

# reinstall service with proper user
gitlab-reinstall:
  cmd.run:
    - name: gitlab-runner uninstall && gitlab-runner install -user {{ gitlab.runner.username }}
    - require:
      - pkg: gitlab-install_pkg

gitlab-create_group:
  group.present:
    - name: {{ gitlab.runner.username }}
    - system: True
    - require:
      - pkg: gitlab-install_pkg

gitlab-install_runserver_create_user:
  user.present:
    - name: {{gitlab.runner.username}}
    - shell: /bin/false
    - home: {{gitlab.runner.home}}
    - groups:
      - gitlab-runner
    - require:
      - group: gitlab-create_group

{% for runner_name, runner in gitlab.runner.runners.items() %}
gitlab-install_runserver3:
  cmd.run:
    - name: "/usr/bin/gitlab-runner register --non-interactive {% for arg, val in runner.items() %} --{{arg}} '{{ val }}' {% endfor %} --name {{ runner_name }}"
    - unless: gitlab-runner verify -n {{ runner_name }}
    - require:
      - user: gitlab-install_runserver_create_user
    - require_in:
      - service: gitlab-runner

{% endfor %}

gitlab-runner:
  service.running:
    - enable: True
    - require:
      - pkg: gitlab-install_pkg
      - cmd: gitlab-install_runserver3
    - watch:
      - cmd: gitlab-reinstall


