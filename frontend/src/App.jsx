import { useState, useEffect } from 'react'

const API = 'http://localhost:8000'

function App() {
  const [fruits, setFruits] = useState([])
  const [name, setName] = useState('')
  const [color, setColor] = useState('')
  const [inSeason, setInSeason] = useState('')

  useEffect(() => {
    const qs = new URLSearchParams()
    if (name) qs.set('name', name)
    if (color) qs.set('color', color)
    if (inSeason !== '') qs.set('in_season', inSeason)
    fetch(`${API}/fruit?${qs}`)
      .then(r => r.json())
      .then(setFruits)
      .catch(console.error)
  }, [name, color, inSeason])

  return (
    <div>
      <h1>Fruit List</h1>
      <div>
        <label>Name: <input value={name} onChange={e => setName(e.target.value)} /></label>
        {' '}
        <label>Color: <input value={color} onChange={e => setColor(e.target.value)} /></label>
        {' '}
        <label>In Season:
          <select value={inSeason} onChange={e => setInSeason(e.target.value)}>
            <option value="">All</option>
            <option value="true">Yes</option>
            <option value="false">No</option>
          </select>
        </label>
      </div>
      <ul>
        {fruits.map(f => (
          <li key={f.name}>
            <strong>{f.name}</strong> — {f.color} — {f.in_season ? 'In Season' : 'Out of Season'}
          </li>
        ))}
      </ul>
      {fruits.length === 0 && <p>No fruit found.</p>}
    </div>
  )
}

export default App
