SARA'S PYTHON CLIENT
====================

This zip holds the files that let your own Python drive a running Sara:
sara.py, the client, and the modules it imports, sara_notebook.py (the
%%gmacs magic for Jupyter), sara_array.py, sara_live.py, sara_params.py,
sara_documents.py, sara_measure.py and sara_start.py. LICENSE is GPLv3.
It is the same set that rides beside the program in every Sara download,
so you need this zip only if you want the client without the program, or
a newer one than the Sara you have.

No Python is in it. You bring Python 3 with numpy, and for notebooks
IPython and ipywidgets too:

  python -m pip install numpy ipython ipywidgets

To use it, unpack the zip beside your script or notebook, or anywhere on
your PYTHONPATH, start Sara with its door open, and attach:

  Windows   double-click sara-with-door.cmd in the Sara download
  Linux     ./sara.x86_64 -- --agent-door

  import sara
  doc = sara.connect()

sara.connect() starts a Sara itself when none listens and it can find one.
The agent guide, AGENTS.md in a Sara download or packaging/agent-guide.md
in the source, lists every step the door takes, and the notebook pages of
the documentation walk through the first cell.

Sara is at https://github.com/MatejZeman02/sara and a bug is
reported there.
